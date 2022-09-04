require "stumpy_png"

id = sprintf("%04d", ARGV[0].to_i)
canvas = StumpyPNG.read("../problem/#{id}.png")
h = canvas.height
w = canvas.width
File.open("../problem/#{id}.txt", "w") do |f|
  f << h << " " << w << "\n"
  h.times do |i|
    w.times do |j|
      pixel = canvas[j, i]
      f << pixel.to_rgba.join(" ") << "\n"
    end
  end
end
