
class Integrate
  def self.command
    i = self.new 
    i.init
  end

  def init
    @todo = Todo.new Dir.getwd

    unless @todo.exists?
      puts "Writing TODO"
      @todo.branches = list.map{ |name| Branch.new name }
      @todo.write
      system "git checkout -B integration/master --no-track develop"
      edit
    end

    puts "Reading TODO"
    @todo.read

    continue
  end

  def continue
    @branch = @todo.next
    return complete if @branch.nil?

    puts "Integrating " + @branch.name

    if @branch.original_commit.nil?
      system "git checkout -B #{@branch.branch_name} --no-track #{@branch.remote_name}"
      @branch.original_commit = `git rev-parse --short HEAD`
      @todo.write
    else
      system "git checkout #{@branch.branch_name}"
    end

    if @branch.branch_commit.nil?
      if system "git rebase -i develop"
        @branch.branch_commit = `git rev-parse --short HEAD`
        @todo.write
      else
        puts "Rebase in progress. Run git integrate continue when finished"
        return
      end
    end

    current_branch = `git rev-parse --abbrev-ref HEAD`.rstrip
    puts "Current branch: #{current_branch} Integration: #{@branch.branch_name}"

    if @branch.final_commit.nil?
      if @branch.branch_name == current_branch
        system "git checkout integration/master"
        unless system "git cherry-pick develop..#{@branch.branch_name}"
          puts "Cherry pick failed. Resolve the conflict then git integrate continue"
          return
        end
      end
      #Assumes we're on integration/master after a cherry-pick
      @branch.final_commit = `git rev-parse --short HEAD`
      @todo.write
    end
    
    continue
  end

  def complete
    puts "Integration complete"
  end

  def edit
    editor = `git config --get core.editor`.rstrip
    system "#{editor} #{@todo.filename}"
  end

  # List codereview branches
  def list
    branches = `git branch -r`.split("\n")
    branches.
      map!(&:strip).
      select {|b| b =~ %r{^origin/codereview} }.
      map! {|b| b[%r{origin/codereview/(.*)}, 1] }
  end
end

class Branch
  attr_accessor :name

  # Original commit of this branch in branch_name
  attr_accessor :original_commit

  # Rebased commit of this branch in branch_name
  attr_accessor :branch_commit

  # Last commit of this branch in integration/master
  attr_accessor :final_commit

  def initialize(name, original_commit = nil, branch_commit = nil, final_commit = nil)
    @name = name
    @original_commit = original_commit
    @branch_commit = branch_commit
    @final_commit = final_commit
  end

  def self.from_line(line)
    self.new *line.split(" ")
  end

  def to_line
    [@name, @original_commit, @branch_commit, @final_commit].join(" ")
  end

  def remote_name
    "origin/codereview/#{name}"
  end

  def branch_name
    "integration/#{name}"
  end

  def incomplete?
    !complete?
  end

  def complete?
    @final_commit.present?
  end
end

class Todo
  attr_accessor :branches
  attr_accessor :filename

  def initialize(wd)
    @wd = wd
    @filename = File.join(@wd, '.git/integrate-todo')
    @branches =[]
  end

  def exists?
    File.exists? @filename
  end

  def read
    lines = File.readlines @filename
    @branches = lines.
      map(&:rstrip).
      select {|l| l.length > 0 && l[0] != '#' }.
      map {|l| Branch.from_line(l) }
  end

  def next
    @branches.find {|b| b.incomplete? }
  end

  def write
    file = <<END
###
# 
#  This is an integrate todo
#
#  Format
#
#  All lines beginning with # will be ignored
#
#  branch_name original_commit integrated_commit
#
###
END
    file += @branches.map(&:to_line).join("\n")
    File.write(@filename, file)
  end

end
