Pod::Spec.new do |s|

  s.name         = "KDCalendar"
  s.version      = "2.0.0"
  s.summary      = "A calendar component with native events support. Prefer Swift Package Manager; CocoaPods support ends after 2.0."

  s.description  = <<-DESC
  A month calendar for iOS written in Swift. It features both vertical and horizontal layout (and scrolling) and, through the optional EventKit subspec, the display of native calendar events.
                   DESC

  s.homepage     = "https://github.com/mmick66/CalendarView"
  s.screenshots  = "https://raw.githubusercontent.com/mmick66/CalendarView/master/Assets/screenshots.png"

  s.license      = { :type => "MIT", :file => "LICENSE" }

  s.author       = "Michael Michailidis"

  s.platform     = :ios, "17.0"

  s.swift_versions = ["5.0"]

  s.source       = { :git => "https://github.com/mmick66/CalendarView.git", :tag => s.version }

  s.default_subspec = 'Core'

  s.subspec 'Core' do |ss|
    ss.source_files = "Sources/KDCalendar/**/*.swift"
  end

  s.subspec 'EventKit' do |ss|
    ss.dependency 'KDCalendar/Core'
    ss.source_files = "Sources/KDCalendarEventKit/**/*.swift"
    ss.frameworks = 'EventKit'
  end

end
