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
      "<a class='#{Page.new(page).tracked? ? 'exists' : 'unknown'}' href='#{page}'>#{page.titleize}</a>"
    end
  end

  def titleize
    self.gsub(/([A-Z]+)([A-Z][a-z])/,'\1 \2').gsub(/([a-z\d])([A-Z])/,'\1 \2')
  end

  def without_ext
    self.sub(File.extname(self), '')
  end
end

class Page
  class << self
    attr_accessor :repo

    def find_all
      return [] if Page.repo.tree.contents.empty?
      Page.repo.tree.contents.collect { |blob| Page.new(blob.name.without_ext) }
    end
  end

  attr_reader :name

  def initialize(name)
    @name = name
  end

  def body
    raw_body.to_html
  end

  def raw_body
    tracked? ? find_blob.data : ''
  end

  def body=(content)
    return if content == raw_body
    File.open(file_name, 'w') { |f| f << content }
    add_to_index_and_commit!
  end

  def tracked?
    !find_blob.nil?
  end

  def to_s
    name
  end

  private
    def find_blob
      Page.repo.tree.contents.detect { |b| b.name == name + PageExtension }
    end

    def add_to_index_and_commit!
      Dir.chdir(GitRepository) { Page.repo.add(base_name) }
      Page.repo.commit_index(commit_message)
    end

    def file_name
      File.join(GitRepository, name + PageExtension)
    end

    def base_name
      File.basename(file_name)
    end

    def commit_message
      tracked? ? "Edited #{name}" : "Created #{name}"
    end
end

use_in_file_templates!

configure do
  GitRepository = File.expand_path(File.dirname(__FILE__) + '/tmp/wiki')
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

helpers do
  def title(title=nil)
    @title = title.to_s unless title.nil?
    @title
  end

  def list_item(page)
    '<a class="page_name" href="/%s">%s</a>' % [page, page.name.titleize]
  end

  def link_to(url, text)
    %Q(<a href="#{url}">#{text}</a>)
  end
end

before { content_type 'text/html', :charset => 'utf-8' }

get('/') { redirect '/' + Homepage }

get '/_list' do
  @pages = Page.find_all
  haml :list
end

get '/:page' do
  @page = Page.new(params[:page])
  @page.tracked? ? haml(:show) : redirect("/e/#{@page.name}")
end

get '/e/:page' do
  @page = Page.new(params[:page])
  haml :edit
end

post '/e/:page' do
  @page = Page.new(params[:page])
  @page.body = params[:body]
  redirect '/' + @page
end

__END__
@@ layout
!!! strict
%html
  %head
    %title= title
    %link{:rel => 'stylesheet', :href => '/_stylesheet.css', :type => 'text/css'}
    - Dir[Sinatra.application.options.public + '/*.css'].each do |css|
      %link{:href => "/#{File.basename(css)}", :type => "text/css", :rel => "stylesheet"}
    - Dir[Sinatra.application.options.public + '/*.js'].reverse.each do |lib|
      %script{:src => "/#{File.basename(lib)}", :type => 'text/javascript'}
    :javascript
      $(document).ready(function() {
        /* title-case-ification */
        document.title = document.title.toTitleCase();
        $('.page').text($('.page').text().toTitleCase());
        $('#content a').each(function(i) {
          var e = $(this)
          e.text(e.text().toTitleCase());
        })
      })
  %body
    #header
      %h1= link_to '/', 'Sinatra'
      %ul#navigation
        %li= link_to '/GetSinatra', 'Get Sinatra'
        %li= link_to '/docs/sinatra/index.html', 'Documentation'
        %li= link_to '/Contribute', 'Contribute'
    #content= yield
    #footer
      &copy; The Sinatra Communauty | powered by
      %a{ :href => "http://github.com/sr/git-wiki" } git-wiki
      which is powered by
      %a{ :href => "http://github.com/bmizerany/sinatra" } Sinatra
      and
      %a{ :href => "http://git-scm.org" } git

@@ show
- title @page.name.titleize
%h1= %Q{<span class="page">#{title}</span> &mdash; <a href="/e/#{@page}">Edit</a>}
.content.edit_area{:id => @page}
  ~"#{@page.body}"

@@ edit
- title "Editing #{@page}"
%h1= %Q{Editing <a class="page" href="/#{@page}">#{@page.name.titleize}</a>}
%form{:method => 'POST', :action => "/e/#{@page}"}
  %textarea#edit_textarea{:name => 'body'}= @page.raw_body
  %label{:for => 'message_textarea'} Message:
  %textarea#message_textarea{:name => 'message', :rows => 2, :cols => 40}
  %p.submit
    %button{:type => :submit} Save as the newest version
    or
    %a.cancel{:href=>"/#{@page}"} go back

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
