# frozen_string_literal: true

require 'digest'
require 'json'
require 'playwright'
require 'tmpdir'

# Loads chrome/extension into Playwright's Chromium and opens its new tab page. Runs inside bin/dev's image.
module ExtensionHelpers
  EXTENSION = File.expand_path('../../extension', __dir__)
  PHRASES = JSON.parse(File.read(File.join(EXTENSION, 'data', 'phrases.json')))

  # Chrome derives an unpacked extension's id from its path: SHA-256, first 32 hex digits, 0-f mapped to a-p.
  def self.extension_id
    Digest::SHA256.hexdigest(EXTENSION)[0, 32].tr('0-9a-f', 'a-p')
  end

  NEWTAB = "chrome-extension://#{extension_id}/newtab.html".freeze

  def self.included(base)
    base.around do |example|
      Dir.mktmpdir do |profile|
        Playwright.create(playwright_cli_executable_path: 'playwright') do |playwright|
          @context = playwright.chromium.launch_persistent_context(
            profile,
            channel: 'chromium', # the new headless mode, which can load extensions
            headless: true,
            args: ["--disable-extensions-except=#{EXTENSION}", "--load-extension=#{EXTENSION}"],
          )
          @errors = []
          @requests = []
          @context.on('request', ->(request) { @requests << request.url })
          example.run
          expect(@errors).to be_empty, "console errors: #{@errors}"
        ensure
          @context&.close
        end
      end
    end
  end

  attr_reader :page

  # Open the new tab, after putting `settings` in chrome.storage.local.
  def open_newtab(**settings)
    @page ||= @context.pages.first || @context.new_page
    @page.on('pageerror', ->(error) { @errors << error.message }) unless @listening
    @page.on('console', ->(msg) { @errors << msg.text if msg.type == 'error' }) unless @listening
    @listening = true
    @page.goto(NEWTAB)
    unless settings.empty?
      @page.evaluate('s => chrome.storage.local.set(s)', arg: settings.transform_keys(&:to_s))
      @page.reload
    end
    @page.wait_for_selector('#left-text:not(:empty)')
    @page
  end

  def text(id) = page.text_content("##{id}")
  def storage = page.evaluate('() => chrome.storage.local.get(null)')
  def press(key) = page.keyboard.press(key)

  # The [phrase, meaning] row the left panel shows (Spanish unless swapped).
  def shown_row(swapped: false)
    shown = text('left-text')
    all_rows.find { |phrase, meaning| (swapped ? meaning : phrase) == shown }
  end

  def all_rows = PHRASES.fetch('es_AR').values.flatten(1)
end
