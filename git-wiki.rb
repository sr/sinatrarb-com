#!/usr/bin/env ruby
$:.unshift *Dir[File.dirname(__FILE__) + '/vendor/**/lib'].to_a
%w(sinatra
grit
fileutils
open-uri
haml
sass
bluecloth
page
helpers).each { |dependency| require dependency }

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
  @revisions = @page.revisions.map do |revision|
    Page.find(params[:page], revision.id)
  end
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
  unless captcha_passed?
    haml :edit
  else
    @page.update!(params[:body], params[:message])
    redirect "/#{@page}"
  end
end
