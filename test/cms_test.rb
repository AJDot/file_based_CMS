# test/cms_test.rb
ENV["RACK_ENV"] = "test"

require "fileutils"

require "rack/test"
require "minitest/autorun"
require "minitest/reporters"
Minitest::Reporters.use!

require_relative "../cms"

class CMSTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    # create data directory
    FileUtils.mkdir_p(data_path)
    # create user.yml for testing
    File.write(credentials_path, "---\n")
    # add an admin user for tests
    save_user_credentials("admin", "super_secret")
  end

  def teardown
    FileUtils.rm_rf(data_path)
    FileUtils.rm(credentials_path)
  end

  def create_document(name, content = "")
    File.open(File.join(data_path, name), "w") do |file|
      file.write(content)
    end
  end

  def session
    last_request.env["rack.session"]
  end

  def admin_session
    { "rack.session" => { username: "admin"} }
  end

  def test_index
    create_document "about.md"
    create_document "changes.txt"

    get "/"

    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "about.md"
    assert_includes last_response.body, "changes.txt"
  end

  def test_viewing_text_document
    create_document "history.txt", "Yukihiro Matsumoto dreams up Ruby."

    get "/history.txt"

    assert_equal 200, last_response.status
    assert_equal "text/plain", last_response["Content-Type"]
    assert_includes last_response.body, "Yukihiro Matsumoto dreams up Ruby."

  end

  def test_viewing_markdown_document
    create_document "about.md", "# Ruby is..."

    get "/about.md"

    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "<h1>Ruby is...</h1>"
  end

  def test_document_not_found
    get "/notafile.ext"

    assert_equal 302, last_response.status
    assert_equal "notafile.ext does not exist.", session[:message]
  end

  def test_editing_document
    create_document "changes.txt"

    get "/changes.txt/edit", {}, admin_session

    assert_equal 200, last_response.status
    assert_includes last_response.body, "<textarea"
    assert_includes last_response.body, %q(<button type="submit")
  end

  def test_editing_document_signed_out
    create_document "changes.txt"

    get "/changes.txt/edit"

    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_updating_document
    post "/changes.txt", {content: "new content"}, admin_session

    assert_equal 302, last_response.status
    assert_equal "changes.txt has been updated.", session[:message]

    get "/changes.txt"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "new content"
  end

  def test_updating_document_signed_out
    post "/changes.txt", {content: "new content"}

    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_view_new_document_form
    get "/new", {}, admin_session

    assert_equal 200, last_response.status
    assert_includes last_response.body, "<input"
    assert_includes last_response.body, %q(<button type="submit">)
  end

  def test_view_new_document_form_signed_out
    get "/new"

    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_create_new_document
    post "/create", {filename: "test.txt"}, admin_session
    assert_equal 302, last_response.status
    assert_equal "test.txt has been created.", session[:message]

    get "/"
    assert_includes last_response.body, "test.txt"
  end

  def test_create_new_document_signed_out
    post "/create", {filename: "test.txt"}

    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_create_new_document_without_filename
    post "/create", {filename: ""}, admin_session
    assert_equal 422, last_response.status
    assert_includes last_response.body, "A name is required."
  end

  def test_create_new_document_without_file_extension
    post "/create", {filename: "changes"}, admin_session

    assert_equal 422, last_response.status
    assert_includes last_response.body, "Must specify one file extension."
  end

  def test_create_new_document_with_unsupported_format
    post "/create", {filename: "changes.unknown"}, admin_session

    assert_equal 422, last_response.status
    assert_includes last_response.body, "File format not supported!"
  end

  def test_create_new_document_with_existing_filename
    create_document "changes.txt"
    post "/create", {filename: "changes.txt"}, admin_session

    assert_equal 422, last_response.status
    assert_includes last_response.body, "File already exists!"
  end

  def test_deleting_document
    create_document "test.txt"

    post "/test.txt/delete", {}, admin_session
    assert_equal 302, last_response.status
    assert_equal "test.txt has been deleted.", session[:message]

    get "/"
    refute_includes last_response.body, %q(href="/test.txt")
  end

  def test_deleting_document_signed_out
    create_document "test.txt"

    post "/test.txt/delete"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_duplicate_document
    create_document "test.txt"

    post "/copy", { file_basename: "test_copy", file_ext: ".txt", file_location: "#{data_path}/test.txt" }, admin_session

    assert_equal 302, last_response.status

    get last_response["Location"]
    assert_includes last_response.body, "The file was copied to test_copy.txt."
  end

  def test_duplicate_document_signed_out
    create_document "test.txt"

    post "/copy", { file_basename: "test_copy", file_ext: ".txt", file_location: "#{data_path}/test.txt" }

    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_duplicate_document_without_filename
    create_document "test.txt"
    post "/copy", { file_basename: "", file_ext: ".txt", file_location: "#{data_path}/test.txt" }, admin_session
    assert_equal 422, last_response.status
    assert_includes last_response.body, "A name is required."
  end

  def test_duplicate_document_with_existing_filename
    create_document "test.txt"
    post "/copy", { file_basename: "test", file_ext: ".txt", file_location: "#{data_path}/test.txt" }, admin_session

    assert_equal 422, last_response.status
    assert_includes last_response.body, "File already exists!"
  end

  def test_signin_form
    get "/users/signin"

    assert_equal 200, last_response.status
    assert_includes last_response.body, %q(<input)
    assert_includes last_response.body, %q(<button type="submit")
  end

  def test_signin
    post "/users/signin", username: "admin", password: "super_secret"
    assert_equal 302, last_response.status
    assert_equal "admin", session[:username]
    assert_equal "Welcome, #{session[:username]}!", session[:message]

    get last_response["Location"]
    assert_includes last_response.body, "Signed in as admin"
  end

  def test_signin_with_bad_credentials
    post "/users/signin", username: "wrong_name", password: "wrong_password"
    assert_equal 422, last_response.status
    assert_nil session[:username]
    assert_includes last_response.body, "Invalid Credentials"
  end

  def test_signout
    get "/", {}, admin_session
    assert_includes last_response.body, "Signed in as admin"

    post "/users/signout"
    get last_response["Location"]

    assert_nil session[:username]
    assert_includes last_response.body, "You have been signed out"
    assert_includes last_response.body, "Sign In"
  end

  def test_signup_form
    get "/users/signup"

    assert_equal 200, last_response.status
    assert_includes last_response.body, %q(<input)
    assert_includes last_response.body, %q(<button type="submit")
    assert_includes last_response.body, "Confirm Password:"
  end

  def test_signup
    post "/users/signup", { username: "testname", password: "testpassword", password_confirm: "testpassword" }
    assert_equal 302, last_response.status
    assert_equal "You are now signed up! Please sign in to access more features.", session[:message]

    assert load_user_credentials["testname"]
  end

  def test_signup_with_existing_username
    post "/users/signup", { username: "admin", password: "super_secret", password_confirm: "super_secret" }
    assert_equal 422, last_response.status
    assert_includes last_response.body, "admin is already taken."
    assert_equal 1, load_user_credentials.size
  end

  def test_signup_with_bad_password_match
    post "/users/signup", { username: "testuser", password: "super_secret", password_confirm: "not_super_secret" }
    assert_equal 422, last_response.status
    assert_includes last_response.body, "Passwords do not match."
    assert_nil load_user_credentials["testuser"]
  end

  def test_signup_with_bad_short_password
    post "/users/signup", { username: "testuser", password: "short", password_confirm: "short" }
    assert_equal 422, last_response.status
    assert_includes last_response.body, "Password must be at least 6 characters."
    assert_nil load_user_credentials["testuser"]
  end
end
