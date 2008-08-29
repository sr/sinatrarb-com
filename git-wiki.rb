#!/usr/bin/env ruby
$:.unshift *Dir[File.dirname(__FILE__) + '/vendor/**/lib'].to_a
%w(sinatra
grit
fileutils
haml
sass
bluecloth).each { |dependency| require dependency }

class String
  def to_html
    BlueCloth.new(self).to_html.linkify
  end

  def linkify
    self.gsub(/([A-Z][a-z]+[A-Z][A-Za-z0-9]+)/) do |page|
      %Q{<a class="" href="/#{Page.css_class_for(page)}">#{page.titleize}</a>}
    end
  end

  def titleize
    self.gsub(/([A-Z]+)([A-Z][a-z])/,'\1 \2').gsub(/([a-z\d])([A-Z])/,'\1 \2')
  end

  def without_ext
    self.sub(File.extname(self), '')
  end
end

class Time
  def distance_in_words_from_now(from_time = 0)
    from_time = from_time.to_time if from_time.respond_to?(:to_time)
    distance_in_minutes = (((self - Time.now).abs)/60).round

    case distance_in_minutes
      when 0..1
        return (distance_in_minutes == 0) ? 'less than a minute' : '1 minute'
      when 2..44           then "#{distance_in_minutes} minutes"
      when 45..89          then 'about 1 hour'
      when 90..1439        then "about #{(distance_in_minutes.to_f / 60.0).round} hours"
      when 1440..2879      then '1 day'
      when 2880..43199     then "#{(distance_in_minutes / 1440).round} days"
      when 43200..86399    then 'about 1 month'
      when 86400..525599   then "#{(distance_in_minutes / 43200).round} months"
      when 525600..1051199 then 'about 1 year'
      else                      "over #{(distance_in_minutes / 525600).round} years"
    end
  end
end

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
    end.last.id
  end

  def short_revision
    revision.chomp[0,7]
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

use_in_file_templates!

configure do
  GitRepository = File.expand_path(ENV['GIT_WIKI_REPO'] || File.dirname(__FILE__) + '/tmp/wiki')
  PageExtension = '.markdown'
  Homepage = 'Home'
  set_option :haml,  :format        => :html4,
                     :attr_wrapper  => '"'

  begin
    Page.repo = Grit::Repo.new(GitRepository)
  rescue Grit::InvalidGitRepositoryError, Grit::NoSuchPathError
    FileUtils.mkdir_p(GitRepository) unless File.directory?(GitRepository)
    Dir.chdir(GitRepository) { `git init` }
    Page.repo = Grit::Repo.new(GitRepository)
  rescue
    abort "#{GitRepository}: Not a git repository. Install your wiki with `rake bootstrap`"
  end
end

error PageNotFound do
  redirect "/e/#{request.env['sinatra.error'].name}"
end

error RevisionNotFound do
  redirect "/#{request.env['sinatra.error'].name}"
end

helpers do
  def title(title=nil)
    @title = title.to_s unless title.nil?
    @title
  end

  def list_item(page)
    %Q{<a class="page_name" href="/#{page}">#{page.name.titleize}</a>}
  end

  def history_item(page, revision)
    [%Q{#{revision.date.distance_in_words_from_now} ago},
     link_to("/h/#{page}/#{revision.id}", revision.short_message)].join(' &mdash; ')
  end

  def link_to(url_or_page, text=nil)
    case url_or_page
    when Page
      %Q{<a class="page" href="/#{url_or_page}">#{url_or_page.name.titleize}</a>}
    else
      %Q{<a href="#{url_or_page}">#{text}</a>}
    end
  end

  def link_to_revision_of(page)
    %Q{<a class="revision" href="/h/#{page}/#{page.revision}">#{page.short_revision}</a>}
  end

  def links_to_actions_for(page)
    [link_to(page),
     edit_link_for(page),
     history_link_for(page)].join(' &mdash; ' )
  end

  def edit_link_for(page)
    link_to("/e/#{page}", 'Edit')
  end

  def history_link_for(page)
    link_to("/h/#{page}", 'History')
  end
end

before { content_type 'text/html', :charset => 'utf-8' }

get('/') { redirect '/' + Homepage }

get '/_list' do
  @pages = Page.find_all
  haml :list
end

get '/:page' do
  @page = Page.find(params[:page])
  haml :show
end

get '/h/:page' do
  @page = Page.find(params[:page])
  haml :history
end

get '/h/:page/:revision' do
  @page = Page.find_revision(params[:page], params[:revision])
  haml :show
end

get '/e/:page' do
  @page = Page.find_or_create(params[:page])
  haml :edit
end

post '/e/:page' do
  @page = Page.find_or_create(params[:page])
  @page.body = params[:body]
  redirect "/#{@page}"
end

__END__
@@ edit
- title "Editing #{@page}"
%h1= "Editing #{link_to(@page)}"
%form{:method => 'POST', :action => "/e/#{@page}"}
  %textarea#edit_textarea{:name => 'body'}= params[:body] || @page.body
  %label{:for => 'message_textarea'} Message:
  %textarea#message_textarea{:name => 'message', :rows => 2, :cols => 40}
  %p.submit
    %button{:type => :submit} Save as the newest version
    or
    = link_to("/#{@page}", 'go back')

@@ history
- title "History of #{@page}"
%h1= "History #{link_to(@page)}"
%ul#revisions
  - @page.revisions.each do |revision|
    %li= history_item(@page, revision)

@@ list
- title "Listing pages"
%h1 All pages
- if @pages.empty?
  %p No pages found.
- else
  %ul#pages_list
    - @pages.each_with_index do |page, index|
      - if (index % 2) == 0
        %li.odd=  list_item(page)
      - else
        %li.even= list_item(page)
