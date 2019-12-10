Pod::Spec.new do |s|

  s.name         = "KDCalendar"
  s.version      = "1.8.3"
  s.summary      = "A calendar component with native events support."

  s.description  = <<-DESC
  This is an implementation of a calendar component for iOS written in Swift 4.0. It features both vertical and horizontal layout (and scrolling) and the display of native calendar events.
                   DESC

  s.homepage     = "https://github.com/mmick66/CalendarView"
  s.screenshots  = "https://image.ibb.co/eiDPnb/screenshot.png"

  s.license      = { :type => "MIT", :file => "LICENSE" }

  s.author       = "Michael Michailidis"

  s.platform     = :ios, "8.0"

  s.swift_versions = [5.0]

  s.source       = { :git => "https://github.com/mmick66/CalendarView.git", :tag => s.version }

  s.default_subspec = 'EventManager'

  s.subspec 'Core' do |ss|
    ss.source_files = "KDCalendar/CalendarView/**/*.{swift}"
  end

  s.subspec 'EventManager' do |ss|
    ss.source_files = "KDCalendar/CalendarView/**/*.{swift}"
    ss.pod_target_xcconfig = { 'SWIFT_ACTIVE_COMPILATION_CONDITIONS' => 'KDCALENDAR_EVENT_MANAGER_ENABLED' }
  end

end
