#!/usr/bin/env ruby
$:.unshift *Dir[File.dirname(__FILE__) + '/vendor/**/lib'].to_a
%w(sinatra
grit
fileutils
haml
sass
bluecloth
page).each { |dependency| require dependency }

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
  error = request.env['sinatra.error']
  error.revision == 'HEAD' ? redirect("/e/#{error.name}") : redirect("/#{error.name}")
end

helpers do
  def title(title=nil)
    @title = title.to_s unless title.nil?
    @title
  end

  def history_item(page, revision)
    precede(revision.short_date + ' ago &mdash; ') do
      link_to_page(page, revision)
      haml_tag(:span, :class => 'commit_message') do
        puts revision.short_message
      end
    end
  end

  def link_to(url, text)
    haml_tag(:a, :href => url) { puts text }
  end

  def link_to_page(page, revision=nil)
    if revision
      attrs = {:class => 'page_revision', :href => "/h/#{page}/#{revision.id}"}
      text = revision.id_abbrev
    end

    haml_tag(:a, attrs || { :href => "/#{page}", :class => 'page' }) do
      puts text || page.name.titleize
    end
  end

  def edit_link_for(page)
    link_to "/e/#{page}", 'Edit'
  end

  def history_link_for(page)
    link_to "/h/#{page}", 'History'
  end

  def revert_link_for(page)
    message = URI.encode "Revert to #{page.revision}"
    link_to "/e/#{page}?body=#{URI.encode(page.body)}&message=#{message}", "Revert"
  end

  def actions_for(page)
    capture_haml(page) do |p|
      link_to_page(p)
      puts ' &mdash; '
      edit_link_for(p)
      puts '/'
      history_link_for(p)
    end
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
  @page = Page.find(params[:page], params[:revision])
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
