# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'open3'
require 'json'
require 'playwright'
require 'tmpdir'

# Loads chrome/extension into Playwright's Chromium and opens its new tab page. Runs inside bin/dev's image.
module ExtensionHelpers
  EXTENSION = File.expand_path('../../extension', __dir__)
  PHRASES = JSON.parse(File.read(File.join(EXTENSION, 'data', 'phrases.json')))

  TERMINAL = File.expand_path('../../../terminal', __dir__)

  # The manifest's "key" fixes the id: SHA-256 of the key, first 32 hex digits, 0-f mapped to a-p.
  def self.extension_id
    key = JSON.parse(File.read(File.join(EXTENSION, 'manifest.json'))).fetch('key')
    Digest::SHA256.hexdigest(key.unpack1('m'))[0, 32].tr('0-9a-f', 'a-p')
  end

  NEWTAB = "chrome-extension://#{extension_id}/newtab.html".freeze

  def self.included(base)
    base.around do |example|
      Dir.mktmpdir do |profile|
        @profile = profile
        link_terminal if example.metadata[:terminal]
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

  # A pretend terminal for the host to read: its cache (learned) and data (mine.psv), outside the repo.
  def terminal_cache = File.join(@profile, 'terminal', 'cache')
  def terminal_home = File.join(@profile, 'terminal', 'home')
  def learned_file = File.join(terminal_cache, 'vozlocal', 'learned')
  def learned_lines = File.exist?(learned_file) ? File.read(learned_file).lines(chomp: true) : []

  def write_terminal(learned: [], mine: [])
    FileUtils.mkdir_p([File.dirname(learned_file), File.join(terminal_home, 'data', 'es_AR')])
    File.write(learned_file, learned.map { |line| "#{line}\n" }.join)
    File.write(File.join(terminal_home, 'data', 'es_AR', 'mine.psv'),
               (['phrase|translation'] + mine.map { |row| row.join('|') }).map { |line| "#{line}\n" }.join)
    target = File.join(terminal_home, 'vozlocal-host')
    File.symlink(File.join(TERMINAL, 'vozlocal-host'), target) unless File.exist?(target)
  end

  # Register the host with this profile's Chromium the way a user would: `voz install-chrome`.
  def link_terminal
    write_terminal unless File.exist?(terminal_home)
    hosts = File.join(@profile, 'NativeMessagingHosts')
    script = "source #{File.join(TERMINAL, 'vozlocal.plugin.zsh')} >/dev/null; VOZLOCAL_CHROME_HOSTS=#{hosts} " \
             "XDG_CACHE_HOME=#{terminal_cache} VOZLOCAL_HOME=#{terminal_home} voz install-chrome"
    out, status = Open3.capture2e('zsh', '-fc', script)
    raise "voz install-chrome failed: #{out}" unless status.success?
  end

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
