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

  it 'hands over marks made in Chrome before it was linked' do
    open_newtab(delay: 30)
    press('l')
    marked = shown_row.join('|')
    press('n')
    press('l')
    expect { storage['learned']&.size == 2 }.to eventually_be_true
    marks = storage['learned']

    write_terminal(learned: ['Che|Hey'])
    link_terminal
    page.reload
    page.wait_for_selector('#left-text:not(:empty)')

    expect { learned_lines.sort == (['Che|Hey'] + marks).sort }.to eventually_be_true
    expect(marks).to include(marked)
    expect(storage['linked']).to be(true)
  end

  it "doesn't hand them over again after the terminal unlearns one", :terminal do
    open_newtab(delay: 30)
    press('l')
    expect { learned_lines.size == 1 }.to eventually_be_true

    File.write(learned_file, '') # unlearned in the terminal
    page.reload
    page.wait_for_selector('#left-text:not(:empty)')

    expect { storage['learned'] == [] }.to eventually_be_true
    expect(learned_lines).to eq([])
  end

  it 'shows a phrase at once when the terminal is slow, and takes its answer when it comes', :terminal do
    open_newtab(delay: 30)
    write_terminal(learned: ['Che|Hey'])
    slow_host(1.3) # well over the page's 0.4 s wait, well under its 2 s limit per call

    page.reload
    page.wait_for_selector('#left-text:not(:empty)')

    # The phrase is up and the terminal hasn't answered yet.
    expect(text('link')).to eq('')
    expect { text('link') == 'Shared with the terminal' }.to eventually_be_true
    expect(storage['learned']).to eq(['Che|Hey'])
  end

  it "says what went wrong when the terminal refuses", :terminal do
    FileUtils.mkdir_p(File.join(terminal_cache, 'vozlocal'))
    File.mkfifo(File.join(terminal_cache, 'vozlocal', 'learned.lock'))
    open_newtab(delay: 30)

    press('l')

    expect { text('link') == 'Not shared with the terminal (learned.lock is not a regular file)' }.to eventually_be_true
    expect(storage['pending'].map { |p| p['key'] }).to eq([shown_row.join('|')])
  end

  it 'keeps the phrase up through a quick ✓ and undo while the terminal is slow to save', :terminal do
    open_newtab(delay: 30)
    slow_host(0.6) # the first ✓ is still being saved when the undo comes
    shown = shown_row

    press('l')
    press('l')

    # First the ✓'s save lands, then the undo's.
    expect { learned_lines == [shown.join('|')] }.to eventually_be_true
    expect { storage['learned'] == [] && learned_lines.empty? }.to eventually_be_true
    expect(shown_row).to eq(shown)
    expect(page.get_attribute('#learned', 'aria-pressed')).to eq('false')
  end

  it 'works without the terminal, and hands marks over once it is linked' do
    open_newtab(delay: 30)
    expect(text('link')).to eq('Not shared with the terminal: run voz install-chrome')
    phrase = shown_row.join('|')

    press('l')
    expect { storage['pending']&.map { |p| [p['key'], p['on']] } == [[phrase, true]] }.to eventually_be_true

    link_terminal
    page.reload
    page.wait_for_selector('#left-text:not(:empty)')

    expect { learned_lines == [phrase] }.to eventually_be_true
    expect(storage['pending']).to eq([])
    expect(text('link')).to eq('Shared with the terminal')
  end
end
