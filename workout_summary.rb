require 'nokogiri'
require 'time'

include Math

# Constants
METER_PER_MILE = 1609.34

# --- Haversine formula ---
def haversine(lat1, lon1, lat2, lon2)
  rad = PI / 180
  r = 6371000 # meters
  dlat = (lat2 - lat1) * rad
  dlon = (lon2 - lon1) * rad
  a = sin(dlat/2)**2 + cos(lat1 * rad) * cos(lat2 * rad) * sin(dlon/2)**2
  c = 2 * atan2(sqrt(a), sqrt(1 - a))
  r * c
end

# --- Format pace from seconds/km or seconds/mile ---
def format_pace(seconds_per_km = 0, unit: :km)
  return "-" if seconds_per_km <= 0
  minutes = (seconds_per_km / 60).floor
  seconds = (seconds_per_km % 60).round
  "#{minutes}:#{format('%02d', seconds)}"
end

# --- Per-minute summary builder ---
def build_minute_summary(data, compute_distance: false)
  summary = []

  data.keys.sort.each do |minute|
    points = data[minute]
    next if points.size < 2

    total_dist = 0.0
    total_time = 0.0
    elevations = []
    heart_rates = []

    (1...points.size).each do |i|
      prev = points[i - 1]
      curr = points[i]
      dist = compute_distance ? haversine(prev[:lat], prev[:lon], curr[:lat], curr[:lon]) : (curr[:dist] - prev[:dist])
      time_diff = curr[:time] - prev[:time]
      total_dist += dist
      total_time += time_diff
    end

    points.each do |p|
      elevations << p[:ele] if p[:ele]
      heart_rates << p[:hr] if p[:hr]
    end

    pace_sec_per_km = total_dist > 0 ? (total_time / (total_dist / 1000)) : 0
    pace_sec_per_mile = total_dist > 0 ? (total_time / (total_dist / METER_PER_MILE)) : 0

    summary << {
      minute: minute + 1,
      pace_km: format_pace(pace_sec_per_km, unit: :km),
      pace_mile: format_pace(pace_sec_per_mile, unit: :mile),
      heart_rate: heart_rates.any? ? (heart_rates.sum / heart_rates.size) : nil,
      elevation: elevations.any? ? (elevations.sum / elevations.size.to_f).round(1) : nil
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

# --- Print output ---
def print_table(rows)
  puts "Minute | Pace (mile) | HR  | Elev (m)"
  puts "-" * 50
  rows.each do |r|
    puts "#{r[:minute].to_s.rjust(6)} | #{r[:pace_mile].ljust(11)} | #{r[:heart_rate].to_s.rjust(3)} | #{r[:elevation].to_s.rjust(8)}"
  end
end

# --- Entry Point ---
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

