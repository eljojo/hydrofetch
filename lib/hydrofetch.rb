# frozen_string_literal: true

require_relative "hydrofetch/version"

# require 'webdrivers'
# require 'webdrivers/chromedriver'
require 'selenium-webdriver'
require 'nokogiri'
require 'capybara'
require 'json'
require 'pry'

::Selenium::WebDriver::Chrome::Service.driver_path = %x(which chromedriver).strip
::Selenium::WebDriver::Chrome.path = %x(which google-chrome-stable).strip

Capybara.register_driver :headless_chrome  do |app|
  options = Selenium::WebDriver::Chrome::Options.new(args: %w[headless no-sandbox disable-gpu])
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

    attr_reader :browser

    def initialize
      setup_browser!
      @usage_chart = nil
      @logger = ::Logger.new($stdout, ::Logger::INFO)
    end

    def setup_browser!
      @browser = Capybara.current_session

      driver = browser.driver.browser
      driver.intercept do |request, &continue|
        uri = URI(request.url)

        @logger.debug("intercepted #{uri}") if uri.to_s =~ /bidgely/
        unless uri.to_s =~ /usage-chart-details/i
          next continue.call(request)
        end
        @logger.debug "intercepted chart request"

        continue.call(request) do |response|
          if response.code == 200
            @logger.info "intercepted chart response"
            @usage_chart = JSON.parse(response.body)
          else
            @logger.warn "error on chart response: #{response.inspect}"
          end
        end
      end
    end

    def run!
      login("", "")

      fetch_usage!

      if @usage_chart
        puts "found chart:"
        puts JSON.pretty_generate(@usage_chart)
      else
        puts "chart not found"
      end
    end

    def fetch_usage!
      @usage_chart = nil
      @logger.info "fetching usage chart"
      browser.visit("https://hydroottawa-new.bidgely.com/dashboard/insights/usage?usage-view=USAGE&usage-mode=DAY")
      browser.find(".usage-chart-disclaimer-v2")
    end

    def login(username, password)
      @logger.info "logging in"
      browser.visit "https://account.hydroottawa.com/login"
      browser.find('#btnLRLogin').click
      browser.find('#loginradius-login-emailid').set(username)
      browser.find('#loginradius-login-password').set(password)
      browser.find('#loginradius-submit-login').native.send_keys(:return)
      wait
      @logger.info "handing over to bidgely"
      browser.visit("https://account.hydroottawa.com/account/usage")
      browser.find('#cons-breakdown-title')
    end

    def wait(extra: false)
      driver = browser.driver.browser
      loop do
        sleep(2)
        if driver.execute_script('return document.readyState') == "complete"
          break
        end
      end
    end
  end
end
