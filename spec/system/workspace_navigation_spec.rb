# frozen_string_literal: true

RSpec.describe 'Workspace navigation' do
  let!(:user) { create(:user) }
  let!(:template) { create(:template, account: user.account, author: user, except_field_types: %w[phone payment]) }

  before do
    sign_in user
  end

  after do
    page.current_window.resize_to(1200, 800)
  end

  it 'moves between templates, submissions and settings from the workspace rail' do
    visit templates_path

    within '.studio-rail' do
      expect(page).to have_css('a[aria-current="page"]', text: 'Templates')
      click_link 'Submissions'
    end

    expect(page).to have_current_path(submissions_path)

    within '.studio-rail' do
      expect(page).to have_css('a[aria-current="page"]', text: 'Submissions')
      click_link 'Settings'
    end

    expect(page).to have_current_path(settings_profile_index_path)

    within '.studio-rail' do
      expect(page).to have_css('a[aria-current="page"]', text: 'Settings')
      click_link 'Templates'
    end

    expect(page).to have_current_path(templates_path)
    expect(page).to have_content(template.name)
  end

  it 'keeps template actions usable on a phone without horizontal overflow' do
    page.current_window.resize_to(390, 844)
    visit templates_path

    expect(page).to have_content(template.name)
    expect(page.evaluate_script('document.documentElement.scrollWidth <= window.innerWidth')).to be(true)

    within '.studio-template-menu' do
      find('label[aria-label="More"]').click
      click_link 'Edit'
    end

    expect(page).to have_current_path(edit_template_path(template), ignore_query: true)
  end
end
