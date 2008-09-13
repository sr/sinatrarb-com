require File.dirname(__FILE__) + '/core_ext'

class PageNotFound < Sinatra::NotFound
  attr_reader :name

  def initialize(name)
    @name = name
  end
end

class RevisionNotFound < PageNotFound; end

class Page
  class << self
    attr_accessor :repo

    def find_all
      return [] if repo.tree.contents.empty?
      repo.tree.contents.collect { |blob| new(blob) }
    end

    def find(name)
      blob = find_blob(name)
      raise PageNotFound.new(name) unless blob
      new(blob)
    end

    def find_revision(name, revision)
      blob = find_blob(name, revision)
      raise RevisionNotFound.new(name) unless blob
      new(blob)
    end

    def find_or_create(name)
      find(name)
    rescue PageNotFound
      new(create_blob_for(name))
    end

    def css_class_for(name)
      find(name)
      'exists'
    rescue PageNotFound
      'unknown'
    end

    private
      def create_blob_for(page_name)
        Grit::Blob.create(repo, :name => page_name + PageExtension, :data => '')
      end

      def find_blob(name, treeish='HEAD')
        repo.tree(treeish)/(name + PageExtension)
      end
  end

  def initialize(blob)
    @blob = blob
  end

  def new?
    body.nil?
  end

  def lastest?
    (revisions.first.tree/@blob.name).id == @blob.id
  end

  def name
    @blob.name.without_ext
  end

  def revision
    # TODO: WTF!!!??
    revisions.select do |commit|
      commit.tree(commit, @blob.name).contents.detect do |blob|
        blob.id == @blob.id
      end
    end.last
  end

  def body
    @blob.data
  end

  def body=(content)
    return if content == body
    File.open(file_name, 'w') { |f| f << content }
    add_to_index_and_commit!
  end

  def revisions
    return [] if new?
    Page.repo.log('master', @blob.name)
  end

  def to_html
    body.linkify.to_html
  end

  def to_s
    name
  end

  private
    def add_to_index_and_commit!
      Dir.chdir(GitRepository) { Page.repo.add(@blob.name) }
      Page.repo.commit_index(commit_message)
    end

    def file_name
      File.join(GitRepository, name + PageExtension)
    end

    def commit_message
      new? ? "Edited #{name}" : "Created #{name}"
    end
end
