# frozen_string_literal: true

module TabsHelper
  def tab_item(label, url, active: false, badge: nil, notification: false)
    render partial: 'shared/tab_item', locals: {
      label:,
      url:,
      active:,
      badge:,
      notification:
    }
  end

  def dynamic_tab_item(label, url_or_urls, badge: nil, notification: false)
    urls = [url_or_urls].flatten
    url = urls.first
    active = urls.any? { |u| current_page?(u) }

    tab_item(label, url, active:, badge:, notification:)
  end
end
