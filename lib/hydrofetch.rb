# frozen_string_literal: true

require_relative "hydrofetch/version"

require "active_support"
require "active_support/core_ext/date_time"

# require 'webdrivers'
# require 'webdrivers/chromedriver'
require 'selenium-webdriver'
require 'nokogiri'

require 'json'
require 'pry'
require 'logger'
require 'uri'
require 'net/http'
require 'pp'
require 'cgi'

USERAGENT = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.1 Safari/605.1.15'

::Selenium::WebDriver::Chrome::Service.driver_path = %x(which chromedriver).strip
::Selenium::WebDriver::Chrome.path = %x(which google-chrome-stable).strip if ENV["APP_ENV"] == "production"

module Hydrofetch
  class Error < StandardError; end
  class Scraper
    attr_reader :driver, :logger

    def initialize(username, password)
      @logger = ::Logger.new($stdout, ::Logger::DEBUG)
      setup_browser!

      @username = username, @password = password
      login

      #@sso_token = login_to_hydro(username, password)
      #@session_token = login_to_bidgely || raise("Couldn't fetch Session Tokens")
    end

    def report
      return @last_report if @last_report && @last_report_expires > Time.now

      @last_report_expires = DateTime.now.end_of_day
      @last_report = fetch_usage_report || raise("couldn't fetch report!")
    end

    def setup_browser!
      options = Selenium::WebDriver::Chrome::Options.new(args: %w[headless no-sandbox disable-gpu])
      @driver = Selenium::WebDriver.for :chrome, options: options
    end

    def login(username = @username, password = @password)
      logger.info "logging in"
      driver.navigate.to "https://account.hydroottawa.com/login"
      if driver.title =~ /Service Unavailable/
        logger.warn("Hydro is down for maintenance")
        return
      end

      driver.find_element(id: 'btnLRLogin').click
      driver.find_element(id: 'loginradius-login-emailid').set(username)
      driver.find_element(id: 'loginradius-login-password').set(password)
      driver.find_element(id: 'loginradius-submit-login').native.send_keys(:return)
      wait
      logger.info "handing over to bidgely"
      driver.navigate.to("https://account.hydroottawa.com/account/usage")
      driver.navigate.to('#cons-breakdown-title')
      wait
    end

    def wait(extra: false)
      loop do
        puts driver.title
        sleep(2)
        if driver.execute_script('return document.readyState') == "complete"
          break
        end
      end
    end

    private

    def login_to_hydro(username, password)
      @logger.info("logging in to loginradius using username/password")
      uri = URI(loginradius_url)
      req = Net::HTTP::Post.new(uri, { 'User-Agent' => USERAGENT, 'Content-Type' => 'application/json' })
      req.body = {"password": password, "email": username }.to_json
      res = Net::HTTP.start(uri.hostname, uri.port, :use_ssl => true ) { |http| http.request(req) }

      unless res.is_a?(Net::HTTPOK)
        @logger.warn("unexpected response when logging into loginradius: #{res}")
        return
      end

      loginradius_data = JSON.parse(res.body)

      @logger.info("fetching hydro session cookies")
      uri = URI('https://account.hydroottawa.com/login')
      req = Net::HTTP::Get.new(uri, { 'User-Agent' => USERAGENT })
      res = Net::HTTP.start(uri.hostname, uri.port, :use_ssl => true ) { |http| http.request(req) }

      if res.is_a?(Net::HTTPFound) && res["location"] =~ /maintenance/
        @logger.warn("Hydro is under maintenance")
        return
      end

      unless res.is_a?(Net::HTTPOK)
        @logger.warn("unexpected response when logging into HydroOttawa: #{res}")
        return
      end

      @logger.debug res.to_hash
      cookies = res.to_hash["set-cookie"].map { |cookie| cookie.split(";",2).first }.join("; ")
      @logger.debug(cookies)

      @logger.info("logging in to hydro using loginradius token")
      uri = URI('https://account.hydroottawa.com/ajax/authenticator')
      req = Net::HTTP::Post.new(uri, { 'User-Agent' => USERAGENT, 'Cookie' => cookies })
      profile = loginradius_data.fetch("Profile")
      formdata = {
        source: 'login',
        uid: profile.fetch("Uid"),
        token: loginradius_data.fetch("access_token"),
        expires: loginradius_data.fetch("expires_in"),
        profile: loginradius_data.fetch("Profile")
      }
      @logger.debug(formdata)
      req.form_data = formdata
      res = Net::HTTP.start(uri.hostname, uri.port, :use_ssl => true ) { |http| http.request(req) }
      cookies = res.to_hash["set-cookie"].map { |cookie| cookie.split(";", 2).first }.join("; ")
      @logger.debug(cookies)

      unless res.is_a?(Net::HTTPOK)
        @logger.warn("unexpected response when logging into HydroOttawa: #{res}")
        return
      end

      hydro_login_response = JSON.parse(res.body)
      unless hydro_login_response.dig("status") == "success"
        @logger.warn("unexpected response when logging into HydroOttawa: #{hydro_login_response}")
        return
      end

      @logger.info("fetching bidgely token from hydro")
      uri = URI('https://account.hydroottawa.com/account/usage')
      req = Net::HTTP::Get.new(uri, { 'User-Agent' => USERAGENT, 'Cookie' => cookies, 'Referer' => 'https://account.hydroottawa.com/' })
      res = Net::HTTP.start(uri.hostname, uri.port, :use_ssl => true ) { |http| http.request(req) }
      # cookies = res.to_hash["set-cookie"].map { |cookie| cookie.split(";",2).first }.join("; ")

      puts res.class
      #puts res.to_hash.inspect
      puts res.body
      raise "exit"
    end

    def login_to_bidgely(sso_token = @sso_token)
      uri = URI("https://usage.hydroottawa.com/api/v1/sso/dashboard")
      @logger.info("logging in to bidgely using hydro token")
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
      return {hehe: true}
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

    def loginradius_url
      "https://api.loginradius.com/identity/v2/auth/login?apiKey=d842e884-2dfb-4c8f-a971-f9eacf8e9f54&loginUrl=&emailTemplate=Verification%20English&verificationUrl=https://account.hydroottawa.com/login"
    end

    def report_url(uuid, token)
      "https://naapi-read.bidgely.com/v2.0/dashboard/users/#{uuid}/usage-chart-details?measurement-type=ELECTRIC&mode=day&start=0&end=#{Time.now.to_i}&date-format=DATE_TIME&locale=en_CA&next-bill-cycle=false&show-at-granularity=false&skip-ongoing-cycle=false'"
    end
  end
end
