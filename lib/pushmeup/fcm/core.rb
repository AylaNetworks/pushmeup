require 'httparty'
require 'cgi'
require 'json'
require_relative 'notification'
require 'logger'


module FCM
  include HTTParty

  base_uri 'https://fcm.googleapis.com/fcm'
  default_timeout 30
  format :json

  @api_key = nil #Should set the fcm api_key here if you don't want to provide it in the client code.

  GROUP_NOTIFICATION_BASE_URI = 'https://fcm.googleapis.com/fcm'

  class << self
    attr_accessor :timeout, :api_key
  end

  def self.send_notification(registration_id, data={}, options={})
    self.send_notifications(registration_id, data, options)
  end

  def self.send_notifications(registration_ids, data={}, options = {})
    notification = Notification.new(registration_ids, data, options)
    self.prepare_and_send(notification, options)
  end


  def self.prepare_and_send(notification, options = {})
    registration_ids = notification.registration_ids

    Rails.logger.info "[Pushmeup::FCM::prepare_and_send] registartion_ids #{registration_ids}"

    post_body = build_post_body(registration_ids, notification.get_options)

    Rails.logger.info "[Pushmeup::FCM::prepare_and_send] request body json #{post_body.to_json}"
    api_key = options[:api_key] || @api_key
    params = {
        body: post_body.to_json,
        headers: {
            'Authorization' => "key=#{api_key}",
            'Content-Type' => 'application/json'
        }
    }

    response = self.post('/send', params)
    build_response(response, registration_ids)
  end

  private

  def self.set_api_key(api_key)
    self.api_key = api_key if self.api_key.nil?
  end

  def self.for_uri(uri)
    current_uri = self.base_uri
    self.base_uri uri
    yield
    self.base_uri current_uri
  end

  def self.build_post_body(registration_ids, options = {})
    ids = registration_ids.is_a?(String) ? [registration_ids] : registration_ids
    data = options
    result = {registration_ids: ids}.merge(data)
    result
  end

  def self.build_response(response, registration_ids = [])
    body = response.body || {}
    response_hash = {body: body, headers: response.headers, status_code: response.code}
    case response.code
      when 200
        response_hash[:response] = 'success'
        body = JSON.parse(body) unless body.empty?
        response_hash[:canonical_ids] = build_canonical_ids(body, registration_ids) unless registration_ids.empty?
        response_hash[:not_registered_ids] = build_not_registered_ids(body, registration_ids) unless registration_ids.empty?
      when 400
        response_hash[:response] = 'Only applies for JSON requests. Indicates that the request could not be parsed as JSON, or it contained invalid fields.'
      when 401
        response_hash[:response] = 'There was an error authenticating the sender account.'
      when 503
        response_hash[:response] = 'Server is temporarily unavailable.'
      when 500..599
        response_hash[:response] = 'There was an internal error in the fcm server while trying to process the request.'
      else
        response_hash[:response] = 'Unknown Error from API.'
    end
    response_hash
  end

  def self.build_canonical_ids(body, registration_ids)
    canonical_ids = []
    unless body.empty?
      if body['canonical_ids'] > 0
        body['results'].each_with_index do |result, index|
          canonical_ids << {old: registration_ids[index], new: result['registration_id']} if has_canonical_id?(result)
        end
      end
    end
    canonical_ids
  end

  def self.build_not_registered_ids(body, registration_id)
    not_registered_ids = []
    unless body.empty?
      if body['failure'] > 0
        body['results'].each_with_index do |result, index|
          not_registered_ids << registration_id[index] if is_not_registered?(result)
        end
      end
    end
    not_registered_ids
  end

  def self.has_canonical_id?(result)
    !result['registration_id'].nil?
  end

  def self.is_not_registered?(result)
    result['error'] == 'NotRegistered'
  end

end