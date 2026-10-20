require 'net/http'
require 'json'

module Tcgdex
  # Minimal read-only client for the free TCGdex REST API (https://tcgdex.dev).
  class Client
    BASE_URL = 'https://api.tcgdex.net/v2/en'.freeze
    class Error < StandardError; end

    def initialize(base_url: BASE_URL, retries: 3)
      @base_url = base_url
      @retries = retries
    end

    def sets
      get('sets')
    end

    def set(id)
      get("sets/#{id}")
    end

    def card(id)
      get("cards/#{id}")
    end

    private

    def get(path)
      attempts = 0
      begin
        attempts += 1
        response = Net::HTTP.get_response(URI("#{@base_url}/#{path}"))
        raise Error, "TCGdex answered #{response.code} for #{path}" unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      rescue Error, SocketError, Timeout::Error, Errno::ECONNRESET, JSON::ParserError => error
        if attempts < @retries
          sleep(attempts)
          retry
        end
        raise Error, "#{error.message} (#{path})"
      end
    end
  end
end
