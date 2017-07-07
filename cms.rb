require "redcarpet"
require "sinatra"
require "sinatra/reloader" if development?
require "tilt/erubis"
require "yaml"
require "bcrypt"

configure do
  enable :sessions
  set :session_secret, 'super secret'
end

def data_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/data", __FILE__)
  else
    File.expand_path("../data", __FILE__)
  end
end

def credentials_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/users.yml", __FILE__)
  else
    File.expand_path("../users.yml", __FILE__)
  end
end

def load_user_credentials
  YAML.load_file(credentials_path)
end

def save_user_credentials(username, password)
  File.open(credentials_path, 'a') { |f| f.puts "#{username}: #{BCrypt::Password.create(password).to_s}"}
end

def render_markdown(text)
  markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
  markdown.render(text)
end

def all_filenames
  pattern = File.join(data_path, "*")
  Dir.glob(pattern).map do |path|
    File.basename(path)
  end
end

def valid_image_extensions
  ['.jpg', '.JPG', '.png']
end

def load_file_content(path)
  content = File.read(path)
  case File.extname(path)
  when ".txt"
    headers["Content-Type"] = "text/plain"
    content
  when ".md"
    erb render_markdown(content)
  when *valid_image_extensions
    image_type = "image/" + File.extname(path)[1..-1]
    headers["Content-Type"] = image_type
    send_file path
  end
end

def error_for_filename(name)
  if name.size == 0
    "A name is required."
  elsif File.extname(name) == ""
    "Must specify file extension."
  elsif !(%w(.md .txt).include? File.extname(name))
    "File format not supported!"
  elsif all_filenames.include? name
    "File already exists!"
  end
end

def user_signed_in?
  session.key?(:username)
end

def require_signed_in_user
  unless user_signed_in?
    session[:message] = "You must be signed in to do that."
    redirect "/"
  end
end

def valid_credentials?(username, password)
  credentials = load_user_credentials

  if credentials.key?(username)
    bcrypt_password = BCrypt::Password.new(credentials[username])
    bcrypt_password == password
  else
    false
  end
end

def error_for_new_username(username)
  credentials = load_user_credentials

  if credentials.key?(username)
    "#{username} is already taken."
  elsif username.size == 0
    "A username is required."
  end
end

def error_for_new_password(password, password_confirm)
  if password != password_confirm
    "Passwords do not match."
  elsif password.size < 6
    "Password must be at least 6 characters."
  end
end


get "/" do
  @files = all_filenames
  erb :index, layout: :layout
end

get "/users/signup" do
  erb :signup
end

post "/users/signup" do
  username = params[:username]
  password = params[:password]
  password_confirm = params[:password_confirm]

  username_error = error_for_new_username(username)
  password_error = error_for_new_password(password, password_confirm)

  if username_error || password_error
    status 422
    session[:message] = username_error || password_error
    erb :signup
  else
    save_user_credentials(username, password)
    session[:message] = "You are now signed up! Please sign in to access more features."
    redirect "/"
  end
end

get "/users/signin" do
  erb :signin
end

post "/users/signin" do
  username = params[:username]

  if valid_credentials?(username, params[:password])
    session[:username] = username
    session[:message] = 'Welcome!'
    redirect "/"
  else
    status 422
    session[:message] = 'Invalid Credentials'
    erb :signin
  end
end

post "/users/signout" do
  session.delete :username
  session[:message] = "You have been signed out."
  redirect "/"
end

get "/new" do
  require_signed_in_user
  erb :new, layout: :layout
end

post "/create" do
  require_signed_in_user
  filename = params[:filename].to_s

  error = error_for_filename(filename)
  if error
    session[:message] = error
    status 422
    erb :new
  else
    file_path = File.join(data_path, filename)

    File.write(file_path, "")
    session[:message] = "#{params[:filename]} has been created."

    redirect "/"
  end
end

post "/copy" do
  require_signed_in_user
  filename = params[:filename].to_s
  @content = params[:content]

  error = error_for_filename(filename)
  if error
    session[:message] = error
    status 422
    erb :copy
  else
    file_path = File.join(data_path, filename)

    File.write(file_path, @content)
    session[:message] = "The file was copied to #{filename}."
    redirect "/"
  end
end

get "/upload" do
  erb :upload
end

post "/upload" do
  file_destination = File.join(data_path, params[:image][:filename])
  file_location = params[:image][:tempfile].path
  FileUtils.copy(file_location, file_destination)
  redirect "/"
end

get "/:filename" do
  file_path = File.join(data_path, params[:filename])

  if File.file?(file_path)
    load_file_content(file_path)
  else
    session[:message] = "#{params[:filename]} does not exist."
    redirect "/"
  end
end

get "/:filename/edit" do
  require_signed_in_user
  file_path = File.join(data_path, params[:filename])

  @filename = params[:filename]
  @content = File.read(file_path)

  erb :edit, layout: :layout
end

get "/:filename/copy" do
  require_signed_in_user
  file_path = File.join(data_path, params[:filename])

  @filename = params[:filename]
  @content = File.read(file_path)

  erb :copy, layout: :layout
end

post "/:filename" do
  require_signed_in_user
  file_path = File.join(data_path, params[:filename])

  File.write(file_path, params[:content])

  session[:message] = "#{params[:filename]} has been updated."
  redirect "/"
end

post "/:filename/delete" do
  require_signed_in_user
  file_path = File.join(data_path, params[:filename])
  File.delete(file_path)

  session[:message] = "#{params[:filename]} has been deleted."
  redirect "/"
end
