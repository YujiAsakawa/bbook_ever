##
# Copyright 2012 Evernote Corporation. All rights reserved.
##
require 'tapp'
require 'pry-byebug'
require 'sinatra'
enable :sessions

# Load our dependencies and configuration settings
$LOAD_PATH.push(File.expand_path(File.dirname(__FILE__)))
require "evernote_config.rb"
OpenSSL::SSL::VERIFY_PEER = OpenSSL::SSL::VERIFY_NONE

##
# Verify that you have obtained an Evernote API key
##
before do
  if OAUTH_CONSUMER_KEY.empty? || OAUTH_CONSUMER_SECRET.empty?
    halt '<span style="color:red">Before using this sample code you must edit evernote_config.rb and replace OAUTH_CONSUMER_KEY and OAUTH_CONSUMER_SECRET with the values that you received from Evernote. If you do not have an API key, you can request one from <a href="http://dev.evernote.com/documentation/cloud/">dev.evernote.com/documentation/cloud/</a>.</span>'
  end
end

helpers do
  def auth_token
    session[:access_token].token if session[:access_token]
  end

  def client
    @client ||= EvernoteOAuth::Client.new(token: auth_token, consumer_key:OAUTH_CONSUMER_KEY, consumer_secret:OAUTH_CONSUMER_SECRET, sandbox: SANDBOX)
  end

  def user_store
    @user_store ||= client.user_store
  end

  def note_store
    @note_store ||= client.note_store
  end

  def en_user
    user_store.getUser(auth_token)
  end

  def notebooks
    @notebooks ||= note_store.listNotebooks(auth_token)
  end

  def total_note_count
    filter = Evernote::EDAM::NoteStore::NoteFilter.new
    counts = note_store.findNoteCounts(auth_token, filter, false)
    notebooks.inject(0) do |total_count, notebook|
      total_count + (counts.notebookCounts[notebook.guid] || 0)
    end
  end
end

##
# Index page
##
get '/' do
  erb :index
end

##
# Reset the session
##
get '/reset' do
  session.clear
  redirect '/'
end

##
# Obtain temporary credentials
##
get '/requesttoken' do
  callback_url = request.url.chomp("requesttoken").concat("callback")
  begin
    session[:request_token] = client.request_token(:oauth_callback => callback_url)
    redirect '/authorize'
  rescue => e
    @last_error = "Error obtaining temporary credentials: #{e.message}"
    erb :error
  end
end

##
# Redirect the user to Evernote for authoriation
##
get '/authorize' do
  if session[:request_token]
    redirect session[:request_token].authorize_url
  else
    # You shouldn't be invoking this if you don't have a request token
    @last_error = "Request token not set."
    erb :error
  end
end

##
# Receive callback from the Evernote authorization page
##
get '/callback' do
  unless params['oauth_verifier'] || session['request_token']
    @last_error = "Content owner did not authorize the temporary credentials"
    halt erb :error
  end
  session[:oauth_verifier] = params['oauth_verifier']
  begin
    session[:access_token] = session[:request_token].get_access_token(:oauth_verifier => session[:oauth_verifier])
    redirect '/list'
  rescue => e
    @last_error = 'Error extracting access token'
    erb :error
  end
end


##
# Access the user's Evernote account and display account data
##
get '/list' do
  # begin
    post_note
    # Get notebooks
    session[:notebooks] = notebooks.map(&:name)
    # Get username
    session[:username] = en_user.username
    # Get total note count
    session[:total_notes] = total_note_count
    erb :index
  # rescue => e
  #   @last_error = "Error listing notebooks: #{e.message}"
  #   erb :error
  # end
end

ENML_HEADER = <<HEADER
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE en-note SYSTEM "http://xml.evernote.com/pub/enml2.dtd">
HEADER

def post_note
  default_notebook_guid = note_store.getDefaultNotebook(auth_token).guid

  books = Dir.new(File.expand_path(File.dirname(__FILE__)) + '/books')
  books.each do |book|
    if /\A([^\.]+)\.txt\z/ =~ book
      puts title = $1.encode('utf-8', 'sjis', :invalid => :replace, :undef => :replace)
      body = open(books.path + '/' + book).readlines.join("<br />\n")
        .encode('sjis', 'utf-8', :invalid => :replace, :undef => :replace)
        .encode('utf-8', 'sjis', :invalid => :replace, :undef => :replace)

      note_content = <<CONTENT
#{ENML_HEADER}
<en-note>#{body}</en-note>
CONTENT

      note = Evernote::EDAM::Type::Note.new
      note.title        = title
      note.notebookGuid = default_notebook_guid
      note.content      = note_content

      note_store.createNote(auth_token, note)
    end
  end
end

__END__

@@ index
<html>
<head>
  <title>Evernote Ruby Example App</title>
</head>
<body>
  <a href="/requesttoken">Click here</a> to authenticate this application using OAuth.
  <% if session[:notebooks] %>
  <hr />
  <h3>The current user is <%= session[:username] %> and there are <%= session[:total_notes] %> notes in their account</h3>
  <br />
  <h3>Here are the notebooks in this account:</h3>
  <ul>
    <% session[:notebooks].each do |notebook| %>
    <li><%= notebook %></li>
    <% end %>
  </ul>
  <% end %>
</body>
</html>

@@ error 
<html>
<head>
  <title>Evernote Ruby Example App &mdash; Error</title>
</head>
<body>
  <p>An error occurred: <%= @last_error %></p>
  <p>Please <a href="/reset">start over</a>.</p>
</body>
</html>
