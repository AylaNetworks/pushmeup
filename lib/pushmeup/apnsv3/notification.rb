require 'securerandom'
require 'json'
require 'logger'

module APNSV3
  class Notification
    attr_reader :device_token
    attr_accessor :alert, :badge, :sound, :content_available, :category, :custom_payload, :url_args, :mutable_content
    attr_accessor :apns_id, :expiration, :priority, :topic, :apns_collapse_id

    def initialize(device_token, message)
      raise "Notification needs to have either a Hash or String" unless message.is_a?(String) or message.is_a?(Hash)

      @device_token = device_token
      @apns_id = SecureRandom.uuid
      if message.is_a?(Hash)
        self.alert = message[:alert]
        self.priority = message[:priority]
        self.expiration = message[:expiration]
        self.apns_collapse_id = message[:apns_collapse_id]
        self.apns_id = message[:apns_id]
        self.topic = message[:bundle_id]
        self.sound = message[:sound]
        self.badge = message[:badge]
        self.custom_payload = message[:other]
        Rails.logger.info "[Pushmeup::APNSV3::initialize] sound: #{message[:sound]}"
      else
        Rails.logger.info "[Pushmeup::APNSV3::initialize] notification message string #{message}"
        self.alert = message
      end
    end

    def body
      JSON.dump(to_hash).force_encoding(Encoding::BINARY)
    end

    private


    def to_hash
      aps = {}
      aps.merge!(alert: alert) if alert
      aps.merge!(badge: badge) if badge
      aps.merge!(sound: sound) if sound
      aps.merge!(category: category) if category
      aps.merge!('content-available' => content_available) if content_available
      aps.merge!('url-args' => url_args) if url_args
      aps.merge!('mutable-content' => mutable_content) if mutable_content

      n = {aps: aps}
      n.merge!(custom_payload) if custom_payload
      Rails.logger.info "[Pushmeup::APNSV3::to_hash] #{n.to_s} #{n}"
      n
    end
  end

end
