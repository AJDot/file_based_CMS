require "sinatra"
require "sinatra/reloader" if development?
require "tilt/erubis"

# configure do
#   set :erb, :escape_html => true
# end

helpers do
  def in_paragraphs(text)
    text.split("\n").map do |paragraph|
      "<p>#{paragraph}</p>"
    end.join("\n")
  end
end

root = File.expand_path("..", __FILE__)

get "/" do
  @files = Dir.glob(root + "/data/*").map do |path|
    File.basename(path)
  end
  erb :index, layout: :layout
end

get "/:filename" do
  file_path = root + "/data/" + params[:filename]

  headers["Content-Type"] = "text/plain"
  File.read(file_path)
end
