require "./common"

START_TIME = Time.utc.to_unix_ms
TL         = 2980
INF        = 1 << 29
RND        = Random.new(2)
L          = 400

class Solver
  def initialize(@id : Int32)
    @target = Target.new(@id)
    assert(@target.h == L && @target.w == L)
  end

  def solve
    blocks = Blocks.new(@target)
    best_blocks = blocks
    if blocks.bs.size == 1
      [20].each do |size|
        blocks = Blocks.new(@target)
        solve_dp(blocks, size)
        debug("size:#{size} cost:#{blocks.total_cost} similarity:#{blocks.similarity(@target)}")
        if blocks.total_cost + blocks.similarity(@target) < best_blocks.total_cost + best_blocks.similarity(@target)
          best_blocks = blocks
        end
      end
    else
      solve_swap(blocks)
      best_blocks = blocks
    end
    diff = best_blocks.similarity(@target)
    cost = best_blocks.total_cost
    debug("score:#{cost + diff} cost:#{cost} similarity:#{diff}")
    return best_blocks.ops
  end

  def solve_dp(blocks, size)
    dp = Array.new(L // size) do
      Array.new(L // size) do
        Array.new(L // size) do
          Array.new(L // size, INF)
        end
      end
    end
    dp_best = Array.new(L // size) do
      Array.new(L // size) do
        Array.new(L // size) do
          Array.new(L // size, 0)
        end
      end
    end
    (L // size).times do |h|
      (L // size).times do |w|
        (L // size - h).times do |bottom|
          top = bottom + h
          (L // size - w).times do |left|
            right = left + w
            fill_dp(blocks, size, dp, dp_best, bottom, left, top, right)
          end
        end
      end
      debug("dp...#{h}")
    end
    debug(dp[0][0][-1][-1])
    recover_dp(blocks, blocks.bs[0], size, dp_best, 0, 0, L // size - 1, L // size - 1)
  end

  def recover_dp(blocks, block, size, dp_best, bottom, left, top, right)
    cut_pos_y = dp_best[bottom][left][top][right] & 0x3FF
    cut_pos_x = dp_best[bottom][left][top][right] >> 10
    if cut_pos_y == 0 && cut_pos_x == 0
      color = @target.best_color(bottom * size, left * size, (top + 1) * size, (right + 1) * size)
      if !(block.areas.size == 1 && block.areas[0].c == color)
        blocks.color(block, color)
      end
    elsif cut_pos_y == 0
      block = recover_dp(blocks, block, size, dp_best, bottom, left, top, cut_pos_x - 1)
      block_left, block_right = blocks.line_cut_vert(block, cut_pos_x * size - block.x)
      block_right = recover_dp(blocks, block_right, size, dp_best, bottom, cut_pos_x, top, right)
      block = blocks.merge(block_left, block_right)
    elsif cut_pos_x == 0
      block = recover_dp(blocks, block, size, dp_best, bottom, left, cut_pos_y - 1, right)
      block_bottom, block_top = blocks.line_cut_horz(block, cut_pos_y * size - block.y)
      block_top = recover_dp(blocks, block_top, size, dp_best, cut_pos_y, left, top, right)
      block = blocks.merge(block_bottom, block_top)
    else
      block = recover_dp(blocks, block, size, dp_best, bottom, left, cut_pos_y - 1, cut_pos_x - 1)

      block_bottom, block_top = blocks.line_cut_horz(block, cut_pos_y * size - block.y)
      block_top = recover_dp(blocks, block_top, size, dp_best, cut_pos_y, left, top, cut_pos_x - 1)
      block = blocks.merge(block_bottom, block_top)

      block_left, block_right = blocks.line_cut_vert(block, cut_pos_x * size - block.x)
      block_right = recover_dp(blocks, block_right, size, dp_best, bottom, cut_pos_x, cut_pos_y - 1, right)
      block_bottom, block_top = blocks.line_cut_horz(block_right, cut_pos_y * size - block_right.y)
      block_top = recover_dp(blocks, block_top, size, dp_best, cut_pos_y, cut_pos_x, top, right)
      block_right = blocks.merge(block_bottom, block_top)
      block = blocks.merge(block_left, block_right)
    end
    return block
  end

  def fill_dp(blocks, size, dp, dp_best, bottom, left, top, right)
    dp[bottom][left][top][right] = dp_paint_cost(size, bottom, left, top, right)
    dp_best[bottom][left][top][right] = 0
    y = bottom * size
    x = left * size
    wh_h = L - y
    wh_w = L - x
    # cut horizontal
    (bottom + 1).upto(top) do |mid|
      cost = dp[bottom][left][mid - 1][right] + dp[mid][left][top][right]
      cost += (OpLineCut.cost * L * L / (wh_h * wh_w)).round.to_i
      cost += (OpMerge.cost * L * L / (wh_w * {mid - bottom, top - mid + 1}.max * size)).round.to_i
      if cost < dp[bottom][left][top][right]
        dp[bottom][left][top][right] = cost
        dp_best[bottom][left][top][right] = mid
      end
    end

    # cut vertical
    (left + 1).upto(top) do |mid|
      cost = dp[bottom][left][top][mid - 1] + dp[bottom][mid][top][right]
      cost += (OpLineCut.cost * L * L / (wh_h * wh_w)).round.to_i
      cost += (OpMerge.cost * L * L / (wh_h * {mid - left, right - mid + 1}.max * size)).round.to_i
      if cost < dp[bottom][left][top][right]
        dp[bottom][left][top][right] = cost
        dp_best[bottom][left][top][right] = mid << 10
      end
    end

    # cut point
    (bottom + 1).upto(top) do |mid_y|
      bottom_len = (mid_y - bottom) * size
      (left + 1).upto(top) do |mid_x|
        left_len = (mid_x - left) * size
        cost = dp[bottom][left][mid_y - 1][mid_x - 1] + dp[bottom][mid_x][mid_y - 1][right] +
               dp[mid_y][left][top][mid_x - 1] + dp[mid_y][mid_x][top][right]
        cost += (OpLineCut.cost * L * L / (wh_h * wh_w)).round.to_i
        cost += (OpMerge.cost * L * L / (wh_w * {bottom_len, wh_h - bottom_len}.max)).round.to_i
        cost += (OpLineCut.cost * L * L / (wh_h * wh_w)).round.to_i
        cost += (OpLineCut.cost * L * L / (wh_h * (wh_w - left_len))).round.to_i
        cost += (OpMerge.cost * L * L / ((wh_w - left_len) * {bottom_len, wh_h - bottom_len}.max)).round.to_i
        cost += (OpMerge.cost * L * L / (wh_h * {left_len, wh_w - left_len}.max)).round.to_i
        if cost < dp[bottom][left][top][right]
          dp[bottom][left][top][right] = cost
          dp_best[bottom][left][top][right] = (mid_x << 10) || mid_y
        end
      end
    end
  end

  def dp_paint_cost(size, bottom, left, top, right)
    y = bottom * size
    x = left * size
    t = (top + 1) * size
    r = (right + 1) * size
    wh_h = L - y
    wh_w = L - x
    color = @target.best_color(y, x, t, r)
    diff_raw = 0.0
    y.upto(t - 1) do |i|
      x.upto(r - 1) do |j|
        diff_raw += color_dist(color, @target.pixel[i][j])
      end
    end
    diff = (diff_raw * 0.005).round.to_i
    return (OpColor.cost * L * L / (wh_h * wh_w)).round.to_i + diff
  end

  def solve_swap(blocks)
    # TODO
  end
end

def main
  solver = Solver.new(ARGV[0].to_i)
  ops = solver.solve
  puts ops.join("\n")
end

def problem1
  target = Target.new(1)
  blocks = Blocks.new(target)
  root = blocks.bs[0]
  blocks.color(root, {0, 74, 173})
  _, b, _, _ = blocks.point_cut(root, 399, 1)
  w0, w1, w2, b = blocks.point_cut(b, 43, 356)
  blocks.color(b, {255, 255, 255})
  b0, b1, b2, b3 = blocks.point_cut(b, 198, 198)
  blocks.color(b1, {0, 0, 0})
  blocks.color(b3, {0, 0, 0})
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
  blocks.color(b1, {0, 74, 173})

  puts blocks.ops.join("\n")
  blocks.create_image("1.png")

  diff = blocks.similarity(target)
  cost = blocks.total_cost
  debug("score:#{cost + diff} cost:#{cost} similarity:#{diff}")
end

main
