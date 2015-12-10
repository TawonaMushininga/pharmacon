module Spree
  class OrderMailer < BaseMailer
    def confirm_email(order, resend = false)
      @order = order.respond_to?(:id) ? order : Spree::Order.find(order)
      @store = @order.store
      subject = (resend ? "[#{Spree.t(:resend).upcase}] " : '')
      subject += "#{@store.name} #{Spree.t('order_mailer.confirm_email.subject')} ##{@order.number}"
      mail(to: @order.email, from: from_address, subject: subject)
    end

    def cancel_email(order, resend = false)
      @order = order.respond_to?(:id) ? order : Spree::Order.find(order)
      @store = @order.store
      subject = (resend ? "[#{Spree.t(:resend).upcase}] " : '')
      subject += "#{@store.name} #{Spree.t('order_mailer.cancel_email.subject')} ##{@order.number}"
      mail(to: @order.email, from: from_address, subject: subject)
    end
  end
end
