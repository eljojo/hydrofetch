# frozen_string_literal: true

require_relative "hydrofetch/version"

require "active_support"
require "active_support/core_ext"

require 'selenium-webdriver'
require 'nokogiri'
require 'capybara'
require 'json'
require 'pry'
require 'logger'
require 'uri'
require 'net/http'
require 'pp'
require 'cgi'

Time.zone = 'America/Toronto'

USERAGENT = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.1 Safari/605.1.15'

::Selenium::WebDriver::Chrome::Service.driver_path = %x(which chromedriver).strip
::Selenium::WebDriver::Chrome.path = %x(which google-chrome-stable).strip if ENV["APP_ENV"] == "production"

Capybara.register_driver :headless_chrome  do |app|
  options = Selenium::WebDriver::Chrome::Options.new(args: %w[headless no-sandbox disable-gpu disable-dev-shm-usage verbose])
  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end

Capybara.javascript_driver = :headless_chrome
Capybara.configure do |config|
  config.default_max_wait_time = 30 # seconds
  config.default_driver = :headless_chrome
end

module Hydrofetch
  class Error < StandardError; end
  class Scraper
    attr_reader :logger

    def initialize(username, password)
      @logger = ::Logger.new($stdout, ::Logger::DEBUG)
      @username, @password = username, password
    end

    def one_day_ago
      return unless report
      # written this way so it fallsback to yesterday's data in case stale
      time_start = Time.zone.now.beginning_of_hour.strftime('%H:%M:%S')
      report.find {|re| re["intervalStartDate"].include?(time_start) }
    end

    def report
      Time.zone = 'America/Toronto' # UGH

      return @last_report if @last_report && @last_report_expires > Time.zone.now

      @last_report_expires = Time.zone.now.end_of_day
      @last_report = fetch_report! || raise("couldn't fetch report!")
    rescue => e
      logger.warn("failed to get report (#{e.message}), will try in the future...")
      @last_report_expires = 1.minute.from_now
      @last_report
    end

    def fetch_report!
      hydro_cookies = login || raise("failed to log into hydro")
      api_session_token = get_api_session_token(hydro_cookies) || raise("failed to get api_session_token")
      api_token = get_api_token(api_session_token) || raise("failed to get api_token")
      get_usage_report(api_token) || raise("failed to get report")
    end

    private

    HYDRO_COOKIE_NAMES = ["hydroottawa_account", "XSRF-TOKEN"]
    def login
      logger.info "logging into hydroottawa.com"
      raise("empty username or password") unless @username && @password
      browser = Capybara.current_session
      browser.visit "https://account.hydroottawa.com/login"
      if browser.title =~ /Service Unavailable/
        logger.warn("Hydro is down for maintenance")
        return
      end

      logger.debug "sending username and password"
      browser.find('#btnLRLogin').click
      browser.find('#loginradius-login-emailid').set(@username)
      browser.find('#loginradius-login-password').set(@password)
      browser.find('#loginradius-submit-login').native.send_keys(:return)
      wait(browser)

      cookies = browser.driver.browser.manage.all_cookies
      missing_cookies = HYDRO_COOKIE_NAMES - cookies.map { |c| c[:name] }.sort
      if missing_cookies.any?
        logger.warn("Missing cookie #{missing_cookies} after logging into hydro")
        return
      end

      cookies
    rescue => e
      logger.debug Capybara.current_session.html
      raise(e)
    end

    def get_api_session_token(cookies)
      @logger.info("fetching api session token from hydro")
      uri = URI('https://account.hydroottawa.com/account/usage')
      req = Net::HTTP::Get.new(uri, { 'User-Agent' => USERAGENT, 'Cookie' => format_cookies(cookies) })
      res = Net::HTTP.start(uri.hostname, uri.port, :use_ssl => true ) { |http| http.request(req) }

      unless res.is_a?(Net::HTTPOK)
        logger.warn("unexpected status code when fetching api session token: #{res.inspect}")
        return
      end

      html = Nokogiri::HTML5.fragment(res.body)
      sessionToken = html.at_css("input[name=sessionToken]")["value"]
      if !sessionToken || sessionToken == ""
        logger.warn("empty API session token returned from Hydro, cookies must be wrong...")
        return
      end

      sessionToken
    end

    def get_api_token(sessionToken)
      uri = URI("https://usage.hydroottawa.com/api/v1/sso/dashboard")
      @logger.info("fetching api_session using api_token")
      req = Net::HTTP::Post.new(uri, { 'User-Agent' => USERAGENT })
      req.form_data = { 'sessionToken' => sessionToken }
      res = Net::HTTP.start(uri.hostname, uri.port, :use_ssl => true ) { |http| http.request(req) }

      unless res.is_a?(Net::HTTPFound) && res["location"]
        @logger.warn("unexpected response when logging in: #{res}")
        return
      end

      session_data = CGI.parse(URI(res["location"]).query)
      uuid, token = session_data["uuid"]&.first, session_data["token"]&.first
      unless uuid && token
        @logger.warn("couldn't find tokens after logging in: #{res['location']}")
        return
      end

      [uuid, token]
    end

    def get_usage_report(api_token)
      logger.info("fetching report")
      uri = URI(report_url(api_token))
      req = Net::HTTP::Get.new(uri, { 'User-Agent' => USERAGENT, 'Authorization' => "Bearer #{api_token[1]}" })
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

    def report_url(api_token)
      uuid, token = api_token
      "https://naapi-read.bidgely.com/v2.0/dashboard/users/#{uuid}/usage-chart-details?measurement-type=ELECTRIC&mode=day&start=0&end=#{Time.now.to_i}&date-format=DATE_TIME&locale=en_CA&next-bill-cycle=false&show-at-granularity=false&skip-ongoing-cycle=false'"
    end

    def wait(browser)
      loop do
        logger.debug "waiting: #{browser.title}"
        sleep(2)
        if browser.execute_script('return document.readyState') == "complete"
          break
        end
      end
    end

    def format_cookies(cookies)
      cookies.map { |c| "#{c[:name]}=#{c[:value]}" }.join('; ')
    end
  end
end
