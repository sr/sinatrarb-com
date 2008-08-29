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
