# frozen_string_literal: true

require_relative 'support/extension'

RSpec.describe 'The new tab page' do
  include ExtensionHelpers

  it 'shows a Spanish phrase, then its meaning once the delay has passed' do
    open_newtab(delay: 3)

    phrase, meaning = shown_row
    expect(phrase).not_to be_nil
    expect(text('lang-left')).to eq('Español (Rioplatense)')
    expect(text('lang-right')).to eq('English')
    expect(text('right-text')).to eq('')
    expect(text('dots')).to match(/\A·+\z/)

    page.wait_for_selector('#right-text:not(:empty)', timeout: 5000)
    expect(text('right-text')).to eq(meaning)
    expect(text('dots')).to eq('')
  end

  it 'shows the meaning straight away with a delay of 0' do
    open_newtab(delay: 0)

    expect(text('right-text')).to eq(shown_row[1])
  end

  it 'still shows a phrase when stored settings are malformed' do
    open_newtab(mine: [nil, ['a'], { 'phrase' => 'b' }, %w[Zarpado Outrageous]], learned: 5, delay: 'x',
                region: 42, swapped: 'yes', last: 7)

    expect([*all_rows, %w[Zarpado Outrageous]].map(&:first)).to include(text('left-text'))
    expect(text('lang-left')).to eq('Español (Rioplatense)')
    page.wait_for_selector('#right-text:not(:empty)', timeout: 5000)
  end

  it 'keeps learned marks from two open tabs' do
    open_newtab(delay: 30)
    other = @context.new_page
    other.goto(ExtensionHelpers::NEWTAB)
    other.wait_for_selector('#left-text:not(:empty)')

    press('l')
    a = shown_row.join('|')
    expect { storage['learned'] == [a] }.to eventually_be_true
    other.keyboard.press('n') while other.text_content('#left-text') == shown_row[0]
    other.keyboard.press('l')
    b = "#{other.text_content('#left-text')}|#{all_rows.to_h[other.text_content('#left-text')]}"

    expect { storage['learned'].sort == [a, b].sort }.to eventually_be_true
    expect(page.get_attribute('#learned', 'aria-pressed')).to eq('true')
  end

  it 'follows a swap made in another tab' do
    open_newtab(delay: 30)
    other = @context.new_page
    other.goto(ExtensionHelpers::NEWTAB)
    other.wait_for_selector('#left-text:not(:empty)')

    other.keyboard.press('s')

    expect { text('lang-left') == 'English' }.to eventually_be_true
  end

  it 'lets Space press a button reached with the keyboard' do
    open_newtab(delay: 30)
    page.focus('#learned')
    page.keyboard.press('Shift+Tab')
    page.keyboard.press('Tab') # focus by keyboard, so it's :focus-visible

    press('Space')

    expect(page.get_attribute('#learned', 'aria-pressed')).to eq('true')
    expect(text('right-text')).to eq('')
  end

  it 'shows the tagline under the name' do
    open_newtab

    expect(text('tagline')).to eq('Learn the Spanish Porteños actually speak, one tab at a time.')
    name, tagline = %w[.brand #tagline].map { |sel| page.locator(sel).bounding_box }
    expect(tagline['y']).to be > name['y']
  end

  it 'names the category it took the phrase from' do
    open_newtab
    category = ExtensionHelpers::PHRASES['es_AR'].find { |_, rows| rows.include?(shown_row) }.first

    expect(text('category')).to eq(category.tr('_', ' ').capitalize)
  end

  it 'reveals at once on Space or a click, and Space then moves to a different phrase' do
    open_newtab(delay: 30)
    first = shown_row

    press('Space')
    expect(text('right-text')).to eq(first[1])

    press('Space')
    expect(shown_row).not_to eq(first)
    expect(text('right-text')).to eq('')

    page.click('#target')
    expect(text('right-text')).to eq(shown_row[1])
  end

  it 'never shows the same phrase twice in a row, across new phrases and new tabs' do
    open_newtab(delay: 30)
    seen = [shown_row]
    10.times do
      press('n')
      seen << shown_row
    end
    5.times do
      page.reload
      page.wait_for_selector('#left-text:not(:empty)')
      seen << shown_row
    end

    expect(seen.each_cons(2).count { |a, b| a == b }).to eq(0)
    expect(storage['last']).to eq(seen.last.join('|'))
  end

  it 'marks a phrase as learned, keeps it after a reload, and stops picking it' do
    open_newtab(delay: 30)
    learned = shown_row

    press('l')
    expect(page.get_attribute('#learned', 'aria-pressed')).to eq('true')
    expect(storage['learned']).to eq([learned.join('|')])

    page.reload
    page.wait_for_selector('#left-text:not(:empty)')
    shown = [shown_row]
    15.times do
      press('n')
      shown << shown_row
    end
    expect(shown).not_to include(learned)
    expect(storage['learned']).to eq([learned.join('|')])
  end

  it 'unmarks a learned phrase when ✓ is clicked again' do
    open_newtab(delay: 30)

    page.click('#learned')
    page.click('#learned')

    expect(page.get_attribute('#learned', 'aria-pressed')).to eq('false')
    expect(storage['learned']).to eq([])
  end

  it 'swaps the languages, and remembers it' do
    open_newtab(delay: 30)
    phrase, meaning = shown_row

    press('s')
    expect(text('lang-left')).to eq('English')
    expect(text('left-text')).to eq(meaning)
    press('Space')
    expect(text('right-text')).to eq(phrase)

    page.reload
    page.wait_for_selector('#left-text:not(:empty)')
    expect(text('lang-left')).to eq('English')
    expect(shown_row(swapped: true)).not_to be_nil
  end

  it 'mixes in phrases synced from the bot' do
    open_newtab(delay: 30, mine: [%w[Zarpado Outrageous]], learned: all_rows.map { |row| row.join('|') })

    # Everything bundled is learned, so the only unlearned phrase is the synced one.
    expect(text('left-text')).to eq('Zarpado')
  end

  it 'keeps both panels the same width during a long countdown' do
    open_newtab(delay: 30)

    widths = page.evaluate("() => [...document.querySelectorAll('.panel')].map(p => p.getBoundingClientRect().width)")
    expect(widths[0]).to be_within(1).of(widths[1])
  end

  it 'follows the dark colour scheme' do
    page_for_scheme = lambda do |scheme|
      page.emulate_media(colorScheme: scheme)
      page.evaluate('() => getComputedStyle(document.body).backgroundColor')
    end
    open_newtab

    expect(page_for_scheme.call('light')).to eq('rgb(255, 255, 255)')
    expect(page_for_scheme.call('dark')).to eq('rgb(31, 31, 31)')
  end

  it 'loads only from the extension itself' do
    open_newtab

    expect(@requests).not_to be_empty
    expect(@requests.reject { |url| url.start_with?("chrome-extension://#{ExtensionHelpers.extension_id}/") }).to eq([])
  end

  it 'is what a new tab opens' do
    open_newtab
    tab = @context.new_page
    tab.goto('chrome://newtab')
    tab.wait_for_selector('#left-text:not(:empty)')

    expect(tab.text_content('.brand')).to eq('VozLocal')
  end
end
