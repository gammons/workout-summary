require 'nokogiri'
require 'time'
require 'terminal-table'
include Math

METER_PER_MILE = 1609.34

# --- Haversine formula ---
def haversine(lat1, lon1, lat2, lon2)
  rad = PI / 180
  r = 6371000 # meters
  dlat = (lat2 - lat1) * rad
  dlon = (lon2 - lon1) * rad
  a = sin(dlat / 2)**2 + cos(lat1 * rad) * cos(lat2 * rad) * sin(dlon / 2)**2
  c = 2 * atan2(sqrt(a), sqrt(1 - a))
  r * c
end

# --- Format pace ---
def format_pace(seconds)
  return "-" if seconds <= 0
  minutes = (seconds / 60).floor
  sec = (seconds % 60).round
  "#{minutes}:#{format('%02d', sec)}"
end

# --- Build summary ---
def build_minute_summary(data, compute_distance: false)
  summary = []

  data.keys.sort.each do |minute|
    points = data[minute]
    next if points.size < 2

    total_dist = 0.0
    total_time = 0.0
    total_elev_change = 0.0
    elevations = []
    heart_rates = []

    (1...points.size).each do |i|
      prev = points[i - 1]
      curr = points[i]

      dist = compute_distance ? haversine(prev[:lat], prev[:lon], curr[:lat], curr[:lon]) : (curr[:dist] - prev[:dist])
      time_diff = curr[:time] - prev[:time]
      elev_diff = curr[:ele].to_f - prev[:ele].to_f

      total_dist += dist
      total_time += time_diff
      total_elev_change += elev_diff
    end

    points.each do |p|
      elevations << p[:ele] if p[:ele]
      heart_rates << p[:hr] if p[:hr]
    end

    pace_sec_per_km = total_dist > 0 ? (total_time / (total_dist / 1000)) : 0
    pace_sec_per_mile = total_dist > 0 ? (total_time / (total_dist / METER_PER_MILE)) : 0
    grade = total_dist > 0 ? ((total_elev_change / total_dist) * 100).round(1) : nil

    summary << {
      minute: minute + 1,
      pace_km: format_pace(pace_sec_per_km),
      pace_mile: format_pace(pace_sec_per_mile),
      heart_rate: heart_rates.any? ? (heart_rates.sum / heart_rates.size) : nil,
      elevation: elevations.any? ? (elevations.sum / elevations.size.to_f).round(1) : nil,
      grade: grade
    }
  end

  summary
end

# --- TCX Parser ---
def parse_tcx(doc)
  doc.remove_namespaces!
  tps = doc.xpath('//Trackpoint')
  return [] if tps.empty?

  start_time = Time.parse(tps.first.at('Time').text)
  data = Hash.new { |h, k| h[k] = [] }

  tps.each do |tp|
    time = Time.parse(tp.at('Time').text)
    minute = ((time - start_time) / 60).floor
    data[minute] << {
      time: time,
      dist: tp.at('DistanceMeters')&.text&.to_f,
      ele: tp.at('AltitudeMeters')&.text&.to_f,
      hr: tp.at('HeartRateBpm/Value')&.text&.to_i
    }
  end

  build_minute_summary(data, compute_distance: false)
end

# --- GPX Parser ---
def parse_gpx(doc)
  doc.remove_namespaces!
  tps = doc.xpath('//trkpt')
  return [] if tps.empty?

  start_time = Time.parse(tps.first.at('time').text)
  data = Hash.new { |h, k| h[k] = [] }

  tps.each do |tp|
    time = Time.parse(tp.at('time').text)
    lat = tp['lat'].to_f
    lon = tp['lon'].to_f
    ele = tp.at('ele')&.text&.to_f
    hr = tp.at('.//hr')&.text&.to_i
    minute = ((time - start_time) / 60).floor

    data[minute] << {
      time: time,
      lat: lat,
      lon: lon,
      ele: ele,
      hr: hr
    }
  end

  build_minute_summary(data, compute_distance: true)
end

# --- Pretty ASCII table output ---
def print_table(rows)
  headings = ['Minute', 'Pace (km)', 'Pace (mile)', 'HR', 'Elev (m)', 'Grade (%)']
  table_rows = rows.map do |r|
    [
      r[:minute],
      r[:pace_km],
      r[:pace_mile],
      r[:heart_rate],
      r[:elevation],
      r[:grade]
    ]
  end

  puts Terminal::Table.new title: "Workout Summary", headings: headings, rows: table_rows
end

# --- Main ---
if ARGV.empty?
  puts "Usage: ruby workout_summary.rb path/to/file.[tcx|gpx]"
  exit 1
end

file = ARGV.first
doc = Nokogiri::XML(File.read(file))

summary =
  if file.end_with?('.tcx')
    parse_tcx(doc)
  elsif file.end_with?('.gpx')
    parse_gpx(doc)
  else
    puts "Unsupported file type"
    exit 1
  end

print_table(summary)
