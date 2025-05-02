module DashboardPort
  def update_dashboard_with_metric(metric)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  def update_dashboard_with_alert(alert)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end
end
