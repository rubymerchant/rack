require 'rack/session/cookie'
require 'rack/mock'

describe Rack::Session::Cookie do
  incrementor = lambda do |env|
    env["rack.session"]["counter"] ||= 0
    env["rack.session"]["counter"] += 1
    hash = env["rack.session"].dup
    hash.delete("session_id")
    Rack::Response.new(hash.inspect).to_a
  end

  session_id = lambda do |env|
    Rack::Response.new(env["rack.session"].inspect).to_a
  end

  nothing = lambda do |env|
    Rack::Response.new("Nothing").to_a
  end

  describe 'Base64' do
    it 'uses base64 to encode' do
      coder = Rack::Session::Cookie::Base64.new
      str   = 'fuuuuu'
      coder.encode(str).should.equal [str].pack('m')
    end

    it 'uses base64 to decode' do
      coder = Rack::Session::Cookie::Base64.new
      str   = ['fuuuuu'].pack('m')
      coder.decode(str).should.equal str.unpack('m').first
    end

    describe 'Marshal' do
      it 'marshals and base64 encodes' do
        coder = Rack::Session::Cookie::Base64::Marshal.new
        str   = 'fuuuuu'
        coder.encode(str).should.equal [::Marshal.dump(str)].pack('m')
      end

      it 'marshals and base64 decodes' do
        coder = Rack::Session::Cookie::Base64::Marshal.new
        str   = [::Marshal.dump('fuuuuu')].pack('m')
        coder.decode(str).should.equal ::Marshal.load(str.unpack('m').first)
      end

      it 'rescues failures on decode' do
        coder = Rack::Session::Cookie::Base64::Marshal.new
        coder.decode('lulz').should.equal nil
      end
    end
  end

  it 'uses a coder' do
    identity = Class.new {
      attr_reader :calls

      def initialize
        @calls = []
      end

      def encode(str); @calls << :encode; str; end
      def decode(str); @calls << :decode; str; end
    }.new
    cookie = Rack::Session::Cookie.new(incrementor, :coder => identity)
    res = Rack::MockRequest.new(cookie).get("/")
    res["Set-Cookie"].should.include("rack.session=")
    res.body.should.equal '{"counter"=>1}'
    identity.calls.should.equal [:decode, :encode]
  end

  it "creates a new cookie" do
    res = Rack::MockRequest.new(Rack::Session::Cookie.new(incrementor)).get("/")
    res["Set-Cookie"].should.include("rack.session=")
    res.body.should.equal '{"counter"=>1}'
  end

  it "loads from a cookie" do
    res = Rack::MockRequest.new(Rack::Session::Cookie.new(incrementor)).get("/")
    cookie = res["Set-Cookie"]
    res = Rack::MockRequest.new(Rack::Session::Cookie.new(incrementor)).
      get("/", "HTTP_COOKIE" => cookie)
    res.body.should.equal '{"counter"=>2}'
    cookie = res["Set-Cookie"]
    res = Rack::MockRequest.new(Rack::Session::Cookie.new(incrementor)).
      get("/", "HTTP_COOKIE" => cookie)
    res.body.should.equal '{"counter"=>3}'
  end

  it "survives broken cookies" do
    res = Rack::MockRequest.new(Rack::Session::Cookie.new(incrementor)).
      get("/", "HTTP_COOKIE" => "rack.session=blarghfasel")
    res.body.should.equal '{"counter"=>1}'
  end

  bigcookie = lambda do |env|
    env["rack.session"]["cookie"] = "big" * 3000
    Rack::Response.new(env["rack.session"].inspect).to_a
  end

  it "barks on too big cookies" do
    lambda{
      Rack::MockRequest.new(Rack::Session::Cookie.new(bigcookie)).
        get("/", :fatal => true)
    }.should.raise(Rack::MockRequest::FatalWarning)
  end

  it "loads from a cookie wih integrity hash" do
    res = Rack::MockRequest.new(Rack::Session::Cookie.new(incrementor, :secret => 'test')).get("/")
    cookie = res["Set-Cookie"]
    res = Rack::MockRequest.new(Rack::Session::Cookie.new(incrementor, :secret => 'test')).
      get("/", "HTTP_COOKIE" => cookie)
    res.body.should.equal '{"counter"=>2}'
    cookie = res["Set-Cookie"]
    res = Rack::MockRequest.new(Rack::Session::Cookie.new(incrementor, :secret => 'test')).
      get("/", "HTTP_COOKIE" => cookie)
    res.body.should.equal '{"counter"=>3}'
  end

  it "ignores tampered with session cookies" do
    app = Rack::Session::Cookie.new(incrementor, :secret => 'test')
    response1 = Rack::MockRequest.new(app).get("/")
    response1.body.should.equal '{"counter"=>1}'

    _, digest = response1["Set-Cookie"].split("--")
    tampered_with_cookie = "hackerman-was-here" + "--" + digest
    response2 = Rack::MockRequest.new(app).get("/", "HTTP_COOKIE" =>
                                               tampered_with_cookie)

    # Tampared cookie was ignored. Counter is back to 1.
    response2.body.should.equal '{"counter"=>1}'
  end

  it "returns the session id in the session hash" do
    app = Rack::Session::Cookie.new(incrementor)
    res = Rack::MockRequest.new(app).get("/")
    res.body.should.equal '{"counter"=>1}'

    app = Rack::Session::Cookie.new(session_id)
    res = Rack::MockRequest.new(app).get("/", "HTTP_COOKIE" => res["Set-Cookie"])
    res.body.should.match(/"session_id"=>/)
    res.body.should.match(/"counter"=>1/)
  end

  it "does not return a cookie if set to secure but not using ssl" do
    app = Rack::Session::Cookie.new(incrementor, :secure => true)
    res = Rack::MockRequest.new(app).get("/")
    res["Set-Cookie"].should.be.nil

    res = Rack::MockRequest.new(app).get("/", "HTTPS" => "on")
    res["Set-Cookie"].should.not.be.nil
  end

  it "does not return a cookie if cookie was not read/written" do
    app = Rack::Session::Cookie.new(nothing)
    res = Rack::MockRequest.new(app).get("/")
    res["Set-Cookie"].should.be.nil
  end

  it "does not return a cookie if cookie was not written (only read)" do
    app = Rack::Session::Cookie.new(session_id)
    res = Rack::MockRequest.new(app).get("/")
    res["Set-Cookie"].should.be.nil
  end

  it "returns even if not read/written if :expire_after is set" do
    app = Rack::Session::Cookie.new(nothing, :expire_after => 3600)
    res = Rack::MockRequest.new(app).get("/")
    res["Set-Cookie"].should.not.be.nil
  end
end
