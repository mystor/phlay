#!/usr/bin/env ruby

require 'docopt'
require 'rugged'
require 'colorize'
require 'net/http'
require 'base64'
require 'tmpdir'
require 'json'

BUGZILLA = URI "https://bugzilla.mozilla.org"

$version = "phlay 0.1.1"
$doc = <<DOCOPT
Phlay your commits onto phabricator

Usage:
  phlay [-y] <commit>
  phlay -h | --help
  phlay --version

Options:
  -y, --yes   Assume yes.
  -h, --help  Print help info.
  --version   Print the current version
DOCOPT

# Simple Conduit API endpoint. Provides only the minimal required API surface
# XXX(nika): Factor this out into a separate gem?
class Conduit
  class Error < StandardError; end
  class Category; end

  def initialize(repo)
    # Read configuration files for conduit
    arcconfig = JSON.load Pathname(repo.workdir) + '.arcconfig'

    arcrc_path = Pathname('~/.arcrc').expand_path
    begin
      arcrc = JSON.load arcrc_path
    rescue IOError, Errno::ENOENT
      arcrc = {}
    end

    # Read the URI from configuration, and get the related token
    @uri = URI.join arcconfig["phabricator.uri"], 'api/'
    @token = arcrc.dig('hosts', @uri.to_s, 'token')

    # Prompt the user to log in if no token is present
    if @token.nil?
      puts "LOGIN TO PHABRICATOR".bold
      puts "Open this page in your browser, and login if necessary:"
      puts @uri + '/conduit/login'
      puts

      print "Paste API Token from that page: "
      @token = STDIN.gets.strip
      if @token.length != 32 || !(@token =~ /^cli-/)
        raise 'The token was invalid or not formatted correctly'
      end
      arcrc['hosts'] ||= {}
      arcrc['hosts'][@uri.to_s] ||= {}
      arcrc['hosts'][@uri.to_s]['token'] = @token
      arcrc_path.write JSON.pretty_generate(arcrc)
    end

    # use metaprogramming to define conduit methods on our object.
    self.do('conduit.query').each do |cmd, spec|
      cmd = cmd.to_s
      *segs, method = cmd.split '.'

      current = self
      segs.each do |seg|
        seg = seg.to_sym
        if !current.respond_to? seg
          cat = Category.new
          current.define_singleton_method(seg) { cat }
        end
        current = current.public_send seg
      end

      # Define the final endpoint method, taking the argument list.
      this = self
      current.define_singleton_method("#{method}!".to_sym) do |args = {}|
        args.keys { |k| raise "bad #{k}" if !spec[:params].include? k }
        this.do cmd, args
      end
    end

    # Determine repository from our callsign
    resp = diffusion.repository.search! :constraints => {
      :callsigns => [arcconfig['repository.callsign']]
    }
    @repository = resp[:data][0]
  end

  # Run a single command on the conduit remote
  def do(cmd_name, args = {})
    params = JSON.dump args.merge(:__conduit__ => { :token => @token })
    resp = Net::HTTP.post_form @uri + cmd_name, 'params' => params,
                                                'output' => 'json',
                                                '__conduit__' => true
    body = JSON.parse resp.body, :symbolize_names => true
    if !body[:error_code].nil?
      raise Conduit::Error, "#{body[:error_code]}: #{body[:error_info]}"
    end
    body[:result]
  end

  attr_accessor :repository
  attr_accessor :uri
end

class Meta
  @@bug_cache = {}
  @@revision_cache = {}
  @@reviewer_cache = {}
  @@git2hg = {}

  # Fetch Meta for a series of commits. Should be in |commit_range| order.
  def self.fetch(commits)
    # Make sure we have our remote hashes
    Meta.init_git2hg commits if $remote_vcs == :hg

    # Wrap each commit into a meta object
    cur = nil
    commits.collect {|c| cur = Meta.new c, cur}
  end

  # Create a single mercurial commit
  def initialize(commit, parent)
    @commit = commit
    @parent = parent
    @transactions = []
    @details = ""

    # Get our mercurial hash if we have one, as well as our parent's
    if $remote_vcs == :hg
      @remote_hash = @@git2hg[@commit.oid]
      @base_hash = @@git2hg[@commit.parents[0].oid]
    else
      @remote_hash = @commit.oid
      @base_hash = @commit.parents[0].oid
    end

    # Bug info
    @bug = if m = @commit.summary.match(/bug\s*([0-9]+)/i)
      @@bug_cache[m[1]] ||= begin
        url = BUGZILLA + "rest/bug/#{m[1]}?include_fields=id,summary,status"
        resp = JSON.parse Net::HTTP.get(url), :symbolize_names => true
        raise "#{resp[:message]}" if resp[:error]
        resp[:bugs].first
      end
    end

    # Revision info
    revision_re = /differential\s+revision:\s*(?:.+\/)?D([0-9]+)/i
    @revision = if m = @commit.message.match(revision_re)
      @@revision_cache[m[1]] ||= begin
        resp = $conduit.differential.revision.search!(
          :constraints => { :ids => [m[1].to_i] },
          :attachments => { :reviewers => true })
        raise "No such revision #{m[1]}" if resp[:data].empty?
        resp[:data].first
      end
    end

    # Determine the revision summary we are going to use. This also skips the
    # first line of the commit message.
    newlines = @commit.message.lines.drop(1).select {|s| !(s =~ revision_re)}
    @new_summary = newlines.to_a.join('').strip

    # If we have a revision, extract depends on information from it.
    dep_re = /depends\s+on\s+D([0-9]+)/i
    if !@revision.nil?
      oldlines = @revision[:fields][:summary].lines.select {|s| !(s =~ dep_re)}
      @old_summary = oldlines.to_a.join('').strip

      if m = @revision[:fields][:summary].match(dep_re)
        @old_depend = m[1].to_i
      end
    end

    # Reviewer info
    reviewer = -> name {
      resp = $conduit.user.search! :constraints => { :usernames => [name] }
      return resp[:data].first if !resp[:data].empty?
      resp = $conduit.project.search! :constraints => { :slugs => [name] }
      return resp[:data].first if !resp[:data].empty?
      raise "unknown reviewer #{name}"
    }
    reviewer_re = /r(?:[?=,][^,\s]+)+/
    @reviewers = @commit.summary.scan(reviewer_re).collect_concat {|g|
      g[2..-1].split(/[?=,]/).collect {|name|
        @@reviewer_cache[name] ||= reviewer.(name)
      }
    }

    # Strip any reviewer information from the title to put on phabricator.
    @new_title = @commit.summary.sub(reviewer_re, '')
    @new_title.sub!(/[\s,.;]*$/, '')

    # Phabricator commit descriptor
    @phab_commits = {
      @remote_hash => {
        :author => @commit.author[:name],
        :authorEmail =>  @commit.author[:email],
        :time => @commit.author[:time].strftime('%s %z'),
      }
    }

    # Generate the diff
    generate_diff
  end

  def list_details
    warnings = []

    # Log this revision's details to the user while we determine changes
    # XXX(nika): Should we do this in a separate method?
    puts
    puts "#{@commit.oid[0, 12].yellow} #{@commit.summary}"
    if $remote_vcs == :hg
      label "Hg Changeset", "#{@remote_hash.yellow} (parent=#{@base_hash[0, 12]})"
    end

    # Are we updating or creating a new revision?
    if @revision.nil?
      update :repositoryPHID, $conduit.repository[:phid]
      label "New Revision", "<repo: #{$conduit.repository[:fields][:name]}>"
    else
      label "Update Rev.", $conduit.uri + "/D#{@revision[:id]}"
    end

    # What changes are we going to be making?
    files, additions, deletions = @git_diff.stat
    label "Changes", "#{files} file(s) (+#{additions}, -#{deletions})".bold
    if !@uploads.empty?
      label "Upload", "#{@uploads.length} binaries"
    end

    if @revision.nil?
      # Details for newly created revision
      update :title, @new_title
      label "Title", @new_title

      update :summary, @new_summary
      if !@new_summary.empty?
        label "Summary", ''
        @new_summary.each_line {|line| puts "    #{line}"}
      end

      if @bug.nil?
        warnings << "no bug # specified"
      else
        update :'bugzilla.bug-id', @bug[:id].to_s
        label "Bug", "Bug #{@bug[:id]} [#{@bug[:status].bold}] #{@bug[:summary]}"
      end
    else
      # Are we updating the revision title?
      if @new_title != @revision[:fields][:title]
        update :title, @new_title
        label "New Title", @new_title
      end

      # Emit warnings if we try to change our dependency graph.
      if !@old_depend.nil?
        if @parent.nil?
          warnings << "current parent D#{@old_depend} not in push"
        elsif @parent.revision.nil? || @old_depend != @parent.revision[:id]
          warnings << "can't change revision D#{@revision[:id]} dependency"
        end
      end

      # If our summary was updated, add a transaction to make the change.
      if @old_summary != @new_summary
        update :summary, @new_summary
        label "New Summary", ''
        @new_summary.each_line {|line| puts "    #{line}"}
      end

      # Emit a warning if the bug number for the revision is mismatched.
      other_bug = @revision[:fields][:'bugzilla.bug-id']
      if other_bug != @bug[:id].to_s
        warnings << "bug mismatch (#{@bug[:id]} != #{other_bug})"
      end
    end

    # Add any new reviewers which are not yet mentioned.
    if @revision.nil?
      to_add = @reviewers
    else
      existing_details = @revision[:attachments][:reviewers][:reviewers]
      existing = existing_details.collect{|r| r[:reviewerPHID]}
      to_add = @reviewers.select{|r| !existing.include? r[:phid]}
    end

    if !to_add.empty?
      # XXX(nika): Mark these reviewers as "blocking"
      update :'reviewers.add', to_add.collect{|r| r[:phid]}
      label "Add Reviewer", to_add.collect{|r|
        if r[:type] == "USER"
          "#{r[:fields][:realName]} [:#{r[:fields][:username]}]"
        else
          "#{r[:fields][:name]}"
        end
      }.join(', ')
    elsif @revision.nil?
      warnings << "no reviewers specified"
    end

    # Print any generated warnings
    warnings.each {|warning|
      puts "  #{'warning'.red}: #{warning.yellow}"
    }
  end

  def label(tag, details)
    puts "  #{tag.ljust(12).cyan.bold} #{details}"
  end

  def update(type, value)
    @transactions << { :type => type, :value => value }
  end

  attr_reader :remote_hash
  attr_reader :phab_commits
  attr_reader :reviewers
  attr_reader :revision
  attr_reader :bug
  attr_reader :diff
  attr_reader :uploads
  attr_reader :new_title
  attr_reader :new_summary
  attr_reader :transactions
  attr_reader :commit

  # Phabricator change type constants
  TYPE_ADD    = 1
  TYPE_CHANGE = 2
  TYPE_DELETE = 3

  # Phabricator file type constants
  FILE_TEXT   = 1
  FILE_BINARY = 3

  private def generate_diff
    # Get the diff between our parent's tree and our tree
    @git_diff = @commit.parents[0].tree.diff @commit.tree, :context_lines => 32767

    changes = []
    @uploads = []
    @git_diff.each do |patch|
      delta = patch.delta
      type = case delta.status
      when :added    then TYPE_ADD
      when :modified then TYPE_CHANGE
      when :deleted  then TYPE_DELETE
      else raise "unhandled status #{delta.status}"
      end

      metadata = {}
      change = {
        :metadata => metadata,
        :oldProperties => {},
        :newProperties => {},
        :oldPath => delta.old_file[:path],
        :currentPath => delta.new_file[:path],
        :addLines => patch.additions,
        :delLines => patch.deletions,
        :isMissingNewNewline => false,
        :isMissingOldNewline => false,
        :type => type,
        :fileType => delta.binary? ? FILE_BINARY : FILE_TEXT,
        :hunks => [],
      }
      changes << change

      if !delta.added?
        change[:oldProperties]['unix:filemode'] =
          delta.old_file[:mode].to_s(8)
      end
      if !delta.deleted?
        change[:newProperties]['unix:filemode'] =
          delta.new_file[:mode].to_s(8)
      end

      patch.each do |hunk|
        corpus = hunk.lines.map do |line|
          case line.line_origin
          when :context  then " #{line.content}"
          when :addition then "+#{line.content}"
          when :deletion then "-#{line.content}"
          when :eof_newline_added then
            change[:isMissingOldNewline] = true
            '\ No newline at end of file'
          when :eof_newline_removed then
            change[:isMissingNewNewline] = true
            '\ No newline at end of file'
          when :eof_no_newline then
            change[:isMissingOldNewline] = true
            change[:isMissingNewNewline] = true
            '\ No newline at end of file'
          else raise "bad line_origin #{line.line_origin}"
          end
        end
        change[:hunks] << {
          :oldOffset => hunk.old_start,
          :oldLength => hunk.old_lines,
          :newOffset => hunk.new_start,
          :newLength => hunk.new_lines,
          :corpus => corpus.join(''),
        }
      end

      # If the file is binary, mark it to be uploaded.
      if delta.binary?
        if !delta.added?
          @uploads << {
            :type => 'old',
            :blob => $repo.lookup(delta.old_file[:oid]),
            :metadata => metadata,
          }
        end

        if !delta.deleted?
          @uploads << {
            :type => 'new',
            :blob => $repo.lookup(delta.new_file[:oid]),
            :metadata => metadata,
          }
        end
      end
    end

    # Conduit |creatediff| endpoint parameters
    @diff = {
      :changes => changes,
      :sourceControlSystem => $remote_vcs,
      :sourceControlPath => '/',
      :sourceControlBaseRevision => @base_hash,
      :creationMethod => 'phlay',
      :lintStatus => 'none',
      :unitStatus => 'none',
      :repositoryPHID => $conduit.repository[:phid],

      # This seems like unnecessarially invasive info to send, and I don't know
      # of a use for it. Let's send some hardcoded values.
      :sourceMachine => 'localhost',
      :sourcePath => '/',
      :branch => 'master',
    }
  end

  def self.init_git2hg(commits)
    # Get the range of commits which need hashes
    all = commit_range(commits.first.parents[0]) {|commit|
      !(`git cinnabar git2hg #{commit.oid}` =~ /0{40}/)
    }
    all.concat commits

    # Get the hg ID of our base commit, and record it.
    base_oid = all.first.parents[0].oid
    @@git2hg[base_oid] = `git cinnabar git2hg #{base_oid}`.strip

    # Create the bundle & parse hashes from it
    Dir.mktmpdir do |dir|
      puts "Computing #{all.length} cinnabar changesets...".yellow.bold

      bundle = "#{dir}/bundle"
      range = "#{base_oid}..#{all.last.oid}"
      system('git', 'cinnabar', 'bundle', '--version', '1', bundle, range)

      open(bundle, 'rb') do |io|
        raise 'bad bundle type' if io.read(6) != 'HG10UN'
        all.each do |commit|
          # Read our header (size = 84), and seek past the body.
          body_size = io.read(4).unpack('N')[0] - 84
          raise 'bad bundle entry' if body_size < 0

          node, p1, p2, changeset = io.read(80).unpack('H40H40H40H40')
          io.seek(body_size, IO::SEEK_CUR)

          # Check our parent chain is sane
          parent = @@git2hg[commit.parents[0].oid]
          raise 'bad bundle parent' if parent != p1

          # Record the mapping
          @@git2hg[commit.oid] = node
        end
      end
    end
  end
end

# Get a range of commits starting at `start`, and ending the commit before the
# predicate block returns `true`. Each commit must have exactly 1 parent.
def commit_range(start)
  commits = []
  current = start
  while !yield current
    commits << current
    raise 'cannot handle merge commits' if current.parents.length > 1
    current = current.parents.first
  end
  commits.reverse!
  return commits
end

def main()
  args = Docopt::docopt $doc
  if args["--version"]
    puts $version
    return
  end

  # Discover our repository root
  $repo = Rugged::Repository.discover()
  $conduit = Conduit.new $repo

  # Check the type of repository being used
  $remote_vcs = $repo.ref('refs/cinnabar/metadata') ? :hg : :git

  # XXX(nika): Allow selecting arbitrary refs.
  head = $repo.rev_parse('HEAD')

  # Get the set of commits we're interested in
  if args["<commit>"].include? '..'
    base, tip = args["<commit>"].split('..', 2).map {|s|
      s.empty? ? head : $repo.rev_parse(s)
    }
    commits = commit_range(tip) {|p| p == base}
  else
    commits = [$repo.rev_parse(args["<commit>"])]
  end

  # Validate that our commit ranges look sane
  raise 'no commits in range' if commits.empty?
  after = commit_range(head) {|p| p == commits.last}

  # Compute and log important information about each commit
  metas = Meta.fetch commits
  metas.each {|meta| meta.list_details}

  # Prompt the user for confirmation
  if !args["--yes"]
    print "\nContinue? (Y/n) ".bold
    if !['y', ''].include? STDIN.gets.strip.downcase
      raise 'user aborted'
    end
    puts
  end

  # Perform uploads
  metas.each {|meta|
    meta.uploads.each {|upload|
      puts "Uploading binary blob #{upload[:blob].oid}".bold.yellow

      content = upload[:blob].content
      phid = $conduit.file.upload! :data_base64 => Base64.strict_encode64(content)
      upload[:metadata][:"#{upload[:type]}:file-size"] = content.length
      upload[:metadata][:"#{upload[:type]}:binary-phid"] = phid
      puts "  PHID = #{phid}"
    }
  }

  # Push updated Diffs
  metas.each {|meta|
    puts "#{'Create Diff'.bold.yellow}      #{meta.new_title.italic}"
    diff = $conduit.differential.creatediff! meta.diff
    $conduit.differential.setdiffproperty! :diff_id => diff[:diffid],
                                           :name => 'local:commits',
                                           :data => JSON.dump(meta.phab_commits)
    puts "  Diff URI = #{diff[:uri]}"
    meta.update :update, diff[:phid]
  }

  # Create/Update revision information
  parent_revision = nil
  parent_commit = metas.first.commit.parent_ids[0]
  metas.each {|meta|
    status = meta.revision.nil? ? 'Create Revision' : 'Update Revision'
    puts "#{status.bold.yellow}  #{meta.new_title.italic}"

    meta.transactions.each {|txn|
      if txn[:type] == :summary && !parent_revision.nil?
        txn[:value] << "\n\nDepends on D#{parent_revision}"
        txn[:value].strip!
      end
    }

    params = { :transactions => meta.transactions }
    if !meta.revision.nil?
      params[:objectIdentifier] = meta.revision[:phid]
    end

    revision = $conduit.differential.revision.edit! params
    uri = $conduit.uri + "/D#{revision[:object][:id]}"
    puts "  Revision URI = #{uri}"
    parent_revision = revision[:object][:id]

    new_message = ("#{meta.commit.summary}" +
                   "\n\n#{meta.new_summary}").strip +
                   "\n\nDifferential Revision: #{uri}"
    parent_commit = Rugged::Commit.create($repo,
      :author => meta.commit.author,
      :committer => meta.commit.committer,
      :message => new_message,
      :parents => [parent_commit],
      :tree => meta.commit.tree)
  }

  # Reparent remaining commits
  after.each {|commit|
    parent_commit = Rugged::Commit.create($repo,
      :author => commit.author,
      :committer => commit.committer,
      :message => commit.message,
      :parents => [parent_commit],
      :tree => commit.tree)
  }

  # Update HEAD to the new reference.
  collection = Rugged::ReferenceCollection.new($repo)
  collection.update($repo.head.resolve, parent_commit)
  puts "Head updated to #{parent_commit}".yellow.bold
end

if __FILE__ == $0
  begin
    main()
  rescue Docopt::Exit => e
    puts e.message
  end
end
