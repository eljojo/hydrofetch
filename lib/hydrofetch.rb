# frozen_string_literal: true

require_relative "hydrofetch/version"

require "active_support"
require "active_support/core_ext/date_time"

require 'json'
require 'pry'
require 'logger'
require 'uri'
require 'net/http'
require 'pp'
require 'cgi'

USERAGENT = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.1 Safari/605.1.15'

module Hydrofetch
  class Error < StandardError; end
  class Scraper
    def initialize(sso_token)
      @sso_token = sso_token
      @logger = ::Logger.new($stdout, ::Logger::INFO)
      @session_token = login || raise("Couldn't fetch Session Tokens")
    end

    def report
      return @last_report if @last_report && @last_report_expires > Time.now

      @last_report = fetch_usage_report || (sleep(5) && login && fetch_usage_report) || raise("couldn't fetch report!")
      @last_report_expires = DateTime.now.end_of_day
      @last_report
    end

    private

    def login(sso_token = @sso_token)
      uri = URI("https://usage.hydroottawa.com/api/v1/sso/dashboard")
      @logger.info("logging in")
      req = Net::HTTP::Post.new(uri, { 'User-Agent' => USERAGENT })
      req.form_data = { 'sessionToken' => sso_token }
      res = Net::HTTP.start(uri.hostname, uri.port, :use_ssl => true ) { |http| http.request(req) }

      unless res.is_a?(Net::HTTPFound) && res["location"]
        @logger.warn("unexpected response when logging in: #{res}")
        return
      end

      session_data = CGI.parse(URI(res["location"]).query)
      uuid = session_data["uuid"]&.first
      token = session_data["token"]&.first
      unless uuid && token
        @logger.warn("couldn't find tokens when logging in: #{res['location']}")
        return
      end

      @session_token = [uuid, token]
    end

    def fetch_usage_report(tokens = @session_token)
      uuid, token = tokens
      @logger.info("fetching report")
      uri = URI(report_url(uuid, token))
      req = Net::HTTP::Get.new(uri, { 'User-Agent' => USERAGENT, 'Authorization' => "Bearer #{token}" })
      res = Net::HTTP.start(uri.hostname, uri.port, :use_ssl => true ) { |http| http.request(req) }
      unless res.is_a?(Net::HTTPOK)
        @logger.warn("unexpected response when fetching report: #{res}")
        return
      end

      parsed_response = JSON.parse(res.body)
      if parsed_response["error"]
        @logger.warn("unexpected error contained in report: #{res['error']}")
        return
      end

      parsed_response.dig("payload", "usageChartDataList").map do |data|
        relevant = data.slice(
          "intervalStart", "intervalEnd", "intervalStartDate", "intervalEndDate", "cost", "consumption", "temperature"
        )
        relevant.merge(tariff: data.dig("touDetails", "touRrcMap").keys.first)
      end
    end

    def report_url(uuid, token)
      "https://naapi-read.bidgely.com/v2.0/dashboard/users/#{uuid}/usage-chart-details?measurement-type=ELECTRIC&mode=day&start=0&end=#{Time.now.to_i}&date-format=DATE_TIME&locale=en_CA&next-bill-cycle=false&show-at-granularity=false&skip-ongoing-cycle=false'"
    end
  end
end
