# frozen_string_literal: true

require 'json'
require 'open3'
require 'tmpdir'
require 'fileutils'

RSpec.describe 'bin/build-data' do
  chrome = File.expand_path('..', __dir__)

  # Run the script against a copy of the repo's layout, so the specs can change terminal/data freely.
  def run_in(root, *args)
    Open3.capture2e(File.join(root, 'chrome', 'bin', 'build-data'), *args)
  end

  around do |example|
    Dir.mktmpdir do |root|
      @root = root
      FileUtils.mkdir_p(File.join(root, 'chrome', 'bin'))
      FileUtils.mkdir_p(File.join(root, 'chrome', 'extension', 'data'))
      FileUtils.cp(File.join(chrome, 'bin', 'build-data'), File.join(root, 'chrome', 'bin'))
      FileUtils.mkdir_p(File.join(root, 'terminal', 'data', 'es_AR'))
      example.run
    end
  end

  def psv(name, body) = File.write(File.join(@root, 'terminal', 'data', 'es_AR', name), body)
  def output = JSON.parse(File.read(File.join(@root, 'chrome', 'extension', 'data', 'phrases.json')))

  it 'bundles each region and category, parsed as voz does' do
    psv('lunfardo.psv', "phrase|translation\nGuita|Money\n\nno separator\nA|b|c\n")
    psv('greeting.psv', "phrase|translation\nChe|Hey\n")

    _, status = run_in(@root)

    expect(status).to be_success
    expect(output).to eq('es_AR' => { 'greeting' => [%w[Che Hey]], 'lunfardo' => [%w[Guita Money], ['A', 'b|c']] })
  end

  it 'leaves out mine.psv' do
    psv('greeting.psv', "phrase|translation\nChe|Hey\n")
    psv('mine.psv', "phrase|translation\nTelo|Hotel\n")

    run_in(@root)

    expect(output['es_AR'].keys).to eq(['greeting'])
  end

  it '--check passes when the file is current and fails after a .psv changes' do
    psv('greeting.psv', "phrase|translation\nChe|Hey\n")
    run_in(@root)

    out, status = run_in(@root, '--check')
    expect([out, status.success?]).to eq(["phrases.json matches terminal/data\n", true])

    psv('greeting.psv', "phrase|translation\nChe|Hey\nBoludo|Dude\n")
    out, status = run_in(@root, '--check')
    expect(status).not_to be_success
    expect(out).to include("doesn't match terminal/data")
  end

  it 'keeps the committed phrases.json in step with terminal/data' do
    out, status = Open3.capture2e(File.join(chrome, 'bin', 'build-data'), '--check')
    expect(status).to be_success, out
  end
end
