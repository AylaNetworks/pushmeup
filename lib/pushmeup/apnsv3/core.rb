require 'net-http2'
require 'openssl'
require 'json'
require 'logger'


module APNSV3

  APPLE_DEVELOPMENT_SERVER_URL = "https://api.development.push.apple.com".freeze
  APPLE_PRODUCTION_SERVER_URL = "https://api.push.apple.com".freeze
  UNIVERSAL_CERTIFICATE_EXTENSION = "1.2.840.113635.100.6.3.6".freeze

  @pem = nil # this should be the path of the pem file not the contentes
  @pass = nil
  @certificate = nil
  @ssl_context = nil

  @mutex = Mutex.new

  @host = nil
  @port = 443
  @topic = nil

  class << self
    attr_accessor :host, :port, :logger
  end

  def self.send_notification(device_token, message, options = {})
    _logger_route = options.has_key?("rails_log_route") ? options[:rails_log_route] : STDOUT
    @logger = Logger.new(_logger_route)

    @host = options[:url] || APPLE_PRODUCTION_SERVER_URL
    @port ||= options[:port]
    @pem = options[:pem]
    @pass = options[:pass]

    @ssl_context = self.ssl_context

    @topic = self.topics[0]
    message.merge!(bundle_id: @topic)
    n = APNSV3::Notification.new(device_token, message)
    self.send_notifications([n], options)
  end

  def self.send_notifications(notifications, options = {})
    responses = []

    @mutex.synchronize do
        responses = notifications.map do |n|
           self.send_individual_notification(n, options)
        end
    end

    responses
  end

  def self.send_individual_notification(notification, options = {})
    Rails.logger.debug "[Pushmeup::APNSV3::send_individual_notification host: #{@host}, port: #{@port}"
    @connect_timeout = options[:connect_timeout] || 30
    @client = NetHttp2::Client.new(@host, ssl_context: @ssl_context, connect_timeout: @connect_timeout)
    response = self.send_push(notification, options)
    @client.close
    response
  end


  protected

  def self.ssl_context
    @certificate = self.certificate
    ctx = OpenSSL::SSL::SSLContext.new
    begin
      Rails.logger.debug "[Pushmeup::APNSV3::ssl_context] getting ssl_context for PKCS12"
      p12 = OpenSSL::PKCS12.new(@certificate, @pass)
      ctx.key = p12.key
      ctx.cert = p12.certificate
    rescue OpenSSL::PKCS12::PKCS12Error
      Rails.logger.debug "[Pushmeup::APNSV3::ssl_context] getting ssl_context for PKey.RSA"
      ctx.key = OpenSSL::PKey::RSA.new(@certificate, @pass)
      ctx.cert = OpenSSL::X509::Certificate.new(@certificate)
    end
    ctx
  end

  def self.certificate
      if @pem.respond_to?(:read)
        cert = @pem.read
        @pem.rewind if @pem.respond_to?(:rewind)
      else
        begin
          cert = File.read(@pem)
        rescue SystemCallError => e
          Rails.logger.info "[Pushmeup::APNSV3::certificate] Does not understand read and its not a path to a file or directory, setting as plain string."
          cert = @pem
        end
      end
      @certificate = cert
    Rails.logger.debug "[Pushmeup::APNSV3::certificate] Returning certificate set"
    @certificate
  end

  def self.topics
    begin
      ext = self.extension(UNIVERSAL_CERTIFICATE_EXTENSION)
      seq = OpenSSL::ASN1.decode(OpenSSL::ASN1.decode(ext.to_der).value[1].value)
      seq.select.with_index { |_, index| index.even? }.map(&:value)
    rescue Exception => e
      Rails.logger.error "[Pushmeup::APNSV3::topics] exception"
      [self.app_bundle_id]
    end
  end

  def self.app_bundle_id
    @ssl_context.cert.subject.to_a.find { |key, *_| key == "UID" }[1]
  end

  def self.extension(oid)
    @ssl_context.cert.extensions.find { |ext| ext.oid == oid }
  end

  def self.send_push(notification, options)
    Rails.logger.debug "[Pushmeup::APNSV3::send_push] Sending request to APNS server for notification #{notification}"
    request = APNSV3::Request.new(notification)

    response = self.send_to_server(notification, request, options)
    @client.close if @client and @client.respond_to? :close
    return response
  end

  def self.send_to_server(notification, request, options)
    if @client.nil?
      msg = "Error creating http2 client for notification to device #{notification.device_token}"
      Rails.logger.info "[Pushmeup::APNSV3::send_to_server] #{msg}"
      raise msg
    end

    Rails.logger.info "[Pushmeup::APNSV3::send_to_server] Adding post to path #{request.path}, with headers #{request.headers} and body #{request.body}"

    response = @client.call(:post, request.path,
                            body: request.body,
                            headers: request.headers,
                            timeout: options[:timeout]
    )

    Rails.logger.info "[Pushmeup::APNSV3::send_to_server] Got response from APNSv3 server parsing response now."
    return self.build_response(response)
  end

  def self.build_response(response)
    status = response.headers[':status'] if response.headers
    if response.body && response.body.length >= 2
      body = JSON.parse response.body
    else
      body = nil
    end
    if status == '200'
      Rails.logger.info "[Pushmeup::APNSV3::build_response] Response successful headers: #{response.headers} and content #{response.body}"
      {:response => 'success', :body => body, :headers => response.headers, :status_code => status}
    else
      Rails.logger.info "[Pushmeup::APNSV3::build_response] Response . Error code #{status} and content #{response.body}"
      {:response => 'failure', :body => body, :headers => response.headers, :status_code => status}
    end
  end

end