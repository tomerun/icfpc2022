require "./common"

START_TIME = Time.utc.to_unix_ms
TL         = 2980
INF        = 1 << 29
RND        = Random.new(2)

class Solver
  def initialize(@id : Int32)
  end

  def solve
    target = Target.new(@id)
    blocks = Blocks.new(target)
    if blocks.bs.size == 1
      root = blocks.bs[0]
      blocks.color(root, target.best_color(0, 0, target.h, target.w))
    end
    diff = blocks.similarity(target)
    cost = blocks.total_cost
    debug("score:#{cost + diff} cost:#{cost} similarity:#{diff}")
    return blocks.ops
  end
end

def main
  solver = Solver.new(ARGV[0].to_i)
  ops = solver.solve
  puts ops.join("\n")
end

main

def problem1
  target = Target.new(1)
  blocks = Blocks.new(target)
  root = blocks.bs[0]
  blocks.color(root, {0, 74, 173, 255})
  _, b, _, _ = blocks.point_cut(root, 399, 1)
  w0, w1, w2, b = blocks.point_cut(b, 43, 356)
  blocks.color(b, {255, 255, 255, 255})
  b0, b1, b2, b3 = blocks.point_cut(b, 198, 198)
  blocks.color(b1, {0, 0, 0, 255})
  blocks.color(b3, {0, 0, 0, 255})
  left = blocks.merge(b0, b3)
  right = blocks.merge(b1, b2)
  left0, left1 = blocks.line_cut_vert(left, 40)
  left1, left2 = blocks.line_cut_vert(left1, 118)
  right0, right1 = blocks.line_cut_vert(right, 40)
  right1, left1 = blocks.swap(left1, right1)
  left = blocks.merge(left0, left1)
  left = blocks.merge(left, left2)
  right = blocks.merge(right0, right1)
  left0, left1 = blocks.line_cut_vert(left, 79)
  left1, left2 = blocks.line_cut_vert(left1, 40)
  right1, right2 = blocks.line_cut_vert(right, 119)
  right0, right1 = blocks.line_cut_vert(right1, 79)
  right1, left1 = blocks.swap(left1, right1)
  b = blocks.merge(left2, right0)
  b = blocks.merge(left1, b)
  b = blocks.merge(left0, b)
  b = blocks.merge(right1, b)
  b = blocks.merge(right2, b)

  lo, hi = blocks.line_cut_horz(b, 198)
  lo0, lo = blocks.line_cut_horz(lo, 40)
  lo1, lo2 = blocks.line_cut_horz(lo, 118)
  hi0, hi1 = blocks.line_cut_horz(hi, 40)
  hi1, lo1 = blocks.swap(lo1, hi1)
  lo = blocks.merge(lo0, lo1)
  lo = blocks.merge(lo, lo2)
  hi = blocks.merge(hi0, hi1)
  lo0, lo1 = blocks.line_cut_horz(lo, 79)
  lo1, lo2 = blocks.line_cut_horz(lo1, 40)
  hi1, hi2 = blocks.line_cut_horz(hi, 119)
  hi0, hi1 = blocks.line_cut_horz(hi1, 79)
  hi1, lo1 = blocks.swap(lo1, hi1)

  b = blocks.merge(lo0, lo1)
  b = blocks.merge(b, lo2)
  b = blocks.merge(b, hi0)
  b = blocks.merge(b, hi1)
  b = blocks.merge(b, hi2)
  left = blocks.merge(b, w0)
  right = blocks.merge(w1, w2)
  b = blocks.merge(left, right)
  b0, b1, b2, b3 = blocks.point_cut(b, 83, 399 - 43 - 39)
  blocks.color(b1, {0, 74, 173, 255})

  puts blocks.ops.join("\n")
  blocks.create_image("1.png")

  diff = blocks.similarity(target)
  cost = blocks.total_cost
  debug("score:#{cost + diff} cost:#{cost} similarity:#{diff}")
end
