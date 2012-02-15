class Spree::Preference < ActiveRecord::Base

  validates :key, :presence => true
  validates :value, :presence => true, :unless => Proc.new { |pref| pref.value_type.to_sym == :boolean && pref.value == false }
  validates :value_type, :presence => true

  # The type conversions here should match
  # the ones in spree::preferences::preferrable#convert_preference_value
  def value
    case self[:value_type].to_sym
    when :string
      self[:value].to_s
    when :password
      self[:value].to_s
    when :decimal
      BigDecimal.new(self[:value].to_s).round(2, BigDecimal::ROUND_HALF_UP)
    when :integer
      self[:value].to_i
    when :boolean
      (self[:value].to_s =~ /^t/i) != nil
    end
  end

  # For the rc releases of 1.0, we stored the object class names, this converts
  # to preferences definition types. This code should eventually be removed.
  # it is called during the load_preferences of the Preferences::Store
  def self.convert_old_value_types(preference)
    return unless [Symbol.to_s, Fixnum.to_s, Bignum.to_s,
                   Float.to_s, TrueClass.to_s, FalseClass.to_s].include? preference.value_type

    case preference.value_type
    when Symbol.to_s
      preference.value_type = 'string'
    when Fixnum.to_s
      preference.value_type = 'integer'
    when Bignum.to_s
      preference.value_type = 'integer'
      preference.value = preference.value.to_f.to_i
    when Float.to_s
      preference.value_type = 'decimal'
    when TrueClass.to_s
      preference.value_type = 'boolean'
      preference.value = "true"
    when FalseClass.to_s
      preference.value_type = 'boolean'
      preference.value = "false"
    end

    preference.save
  end

end
