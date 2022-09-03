require "./common"

START_TIME = Time.utc.to_unix_ms
TL         = 2980
INF        = 1 << 29
RND        = Random.new(2)

class Solver
  target = Target.new(1)
  blocks = Blocks.new(target)
  root = blocks.bs[0]
  blocks.color(root, {0, 74, 173, 255})
  _, _, _, b = blocks.point_cut(root, 40, 360)
  blocks.color(b, {255, 255, 255, 255})
  lo, hi = blocks.line_cut_horz(b, 200)
  lo, hi = 2.times.map do |i|
    b = {lo, hi}[i]
    lines = [] of Block
    8.times do |j|
      left, b = blocks.line_cut_vert(b, 40)
      if (i + j) % 2 == 1
        blocks.color(left, {0, 0, 0, 255})
      end
      lines << left
    end
    if (i + lines.size) % 2 == 1
      blocks.color(b, {0, 0, 0, 255})
    end
    lines.reverse_each do |mb|
      b = blocks.merge(b, mb)
    end
    b
  end.to_a
  lo0, lo = blocks.line_cut_horz(lo, 40)
  lo1, lo2 = blocks.line_cut_horz(lo, 120)
  hi0, hi1 = blocks.line_cut_horz(hi, 40)
  hi, lo = blocks.swap(lo1, hi1)
  _, lo = blocks.line_cut_horz(lo, 40)
  lo, _ = blocks.line_cut_horz(lo, 40)
  _, hi = blocks.line_cut_horz(hi, 40)
  hi, _ = blocks.line_cut_horz(hi, 40)
  blocks.swap(lo, hi)

  blocks.output_ops(STDOUT)
  blocks.create_image("1.png")

  diff = blocks.similarity(target)
  cost = blocks.total_cost
  debug("score:#{cost + diff} cost:#{cost} similarity:#{diff}")
end
