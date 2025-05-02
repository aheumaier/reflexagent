module NotificationPort
  def send_alert(alert)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  def send_message(channel, message)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end
end
