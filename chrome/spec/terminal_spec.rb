# frozen_string_literal: true

require_relative 'support/extension'

# The extension and the terminal share learned phrases and mine.psv through vozlocal-host.
RSpec.describe 'Sharing with the terminal' do
  include ExtensionHelpers

  let(:bundled) { all_rows.map { |row| row.join('|') } }

  it "shows the terminal's own phrases and skips what it has learned", :terminal do
    write_terminal(learned: bundled, mine: [%w[Zarpado Outrageous]])
    open_newtab(delay: 30)

    expect(text('left-text')).to eq('Zarpado')
    expect(text('link')).to eq('Shared with the terminal')
  end

  it "writes ✓ to the terminal's learned file, and takes it away on undo", :terminal do
    open_newtab(delay: 30)
    phrase = shown_row.join('|')

    press('l')
    expect { learned_lines == [phrase] }.to eventually_be_true

    press('l')
    expect { learned_lines.empty? }.to eventually_be_true
  end

  it 'sees a phrase learned with yas on the next new tab', :terminal do
    open_newtab(delay: 30)
    phrase = shown_row.join('|')

    File.write(learned_file, "#{phrase}\n", mode: 'a') # what yas does
    page.reload
    page.wait_for_selector('#left-text:not(:empty)')

    expect(storage['learned']).to eq([phrase])
    expect(shown_row.join('|')).not_to eq(phrase) # learned (and shown last), so it isn't picked
  end

  it 'works without the terminal, and hands marks over once it is linked' do
    open_newtab(delay: 30)
    expect(text('link')).to eq('Not shared with the terminal: run voz install-chrome')
    phrase = shown_row.join('|')

    press('l')
    expect { storage['pending'] == [{ 'key' => phrase, 'on' => true }] }.to eventually_be_true

    link_terminal
    page.reload
    page.wait_for_selector('#left-text:not(:empty)')

    expect { learned_lines == [phrase] }.to eventually_be_true
    expect(storage['pending']).to eq([])
    expect(text('link')).to eq('Shared with the terminal')
  end
end
