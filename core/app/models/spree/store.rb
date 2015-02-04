module Spree
  class Store < Spree::Base
    validates :code, presence: true, uniqueness: { allow_blank: true }
    validates :name, presence: true
    validates :url, presence: true
    validates :mail_from_address, presence: true

    before_create :ensure_default_exists_and_is_unique
    before_destroy :validate_not_default

    scope :by_url, lambda { |url| where("url like ?", "%#{url}%") }

    preference :analytics_id, :string

    def self.current(domain = nil)
      current_store = domain ? Store.by_url(domain).first : nil
      current_store || Store.default
    end

    def self.default
      where(default: true).first || new
    end

    def analytics_id
      get_preference :analytics_id
    end

    private

    def ensure_default_exists_and_is_unique
      if default
        Store.update_all(default: false)
      elsif Store.where(default: true).count == 0
        self.default = true
      end
    end

    def validate_not_default
      errors.add(:base, :cannot_destroy_default_store) if default
    end
  end
end
