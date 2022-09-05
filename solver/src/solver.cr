require "./common"

START_TIME = Time.utc.to_unix_ms
TL         = 2980
INF        = 1 << 29
RND        = Random.new(2)
L          = 400

MERGE_BEST_M = {
  40 => 5,
  25 => 6,
  20 => 7,
}

class Solver
  def initialize(@id : Int32)
    @target = Target.new(@id)
    assert(@target.h == L && @target.w == L)
  end

  def solve
    blocks = Blocks.new(@target)
    best_blocks = blocks
    dp_sizes = [20]
    if blocks.bs.size == 1
      dp_sizes.each do |size|
        blocks = Blocks.new(@target)
        solve_dp(blocks, size)
        debug("size:#{size} cost:#{blocks.total_cost} similarity:#{blocks.similarity(@target)}")
        if blocks.total_cost + blocks.similarity(@target) < best_blocks.total_cost + best_blocks.similarity(@target)
          best_blocks = blocks
        end
      end
    else
      # 2.upto(10) do |i|
      #   blocks = Blocks.new(@target)
      #   merge_blocks(blocks, i)
      #   best_blocks = blocks
      # end
      dp_sizes.each do |size|
        blocks = Blocks.new(@target)
        merge_blocks(blocks, MERGE_BEST_M[blocks.bs[0].h])
        assert(blocks.bs.size == 1)
        solve_dp(blocks, size)
        debug("size:#{size} cost:#{blocks.total_cost} similarity:#{blocks.similarity(@target)}")
        if blocks.total_cost + blocks.similarity(@target) < best_blocks.total_cost + best_blocks.similarity(@target)
          best_blocks = blocks
        end
      end
      # solve_swap(blocks)
    end
    diff = best_blocks.similarity(@target)
    cost = best_blocks.total_cost
    debug("score:#{cost + diff} cost:#{cost} similarity:#{diff}")
    return best_blocks.ops
  end

  def merge_blocks(blocks, m)
    size = blocks.bs[0].h
    bs = blocks.bs.sort_by { |b| {b.y, b.x} }.group_by { |b| b.y }
    n = bs.size
    rows = bs.keys.sort.first(m).map do |y|
      b = bs[y][0]
      1.upto(bs[y].size - 1) do |i|
        b = blocks.merge(b, bs[y][i])
      end
      b
    end.to_a
    b = rows[0]
    1.upto(m - 1) do |i|
      b = blocks.merge(b, rows[i])
    end
    cols = (n // 2).times.map do |i|
      cur, b = blocks.line_cut_vert(b, size)
      cells = blocks.bs.select { |b| b.x == cur.x && b != cur }.sort_by { |b| b.y }
      cells.each do |cell|
        cur = blocks.merge(cur, cell)
      end
      cur
    end.to_a
    left = blocks.merge_multi(cols)
    l_b, t_b = blocks.line_cut_horz(left, size * m)
    b = blocks.merge(l_b, b)
    cols = (n // 2).times.map do |i|
      b, cur = blocks.line_cut_vert(b, b.w - size)
      cells = blocks.bs.select { |b| b.x == cur.x && b != cur }.sort_by { |b| b.y }
      cells.each do |cell|
        cur = blocks.merge(cur, cell)
      end
      cur
    end.to_a
    left = blocks.merge(b, t_b)
    b = blocks.merge_multi([left] + cols.reverse)
    debug(["merge_cost", m, blocks.total_cost])
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
    (left + 1).upto(right) do |mid|
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
      (left + 1).upto(right) do |mid_x|
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
    bs = blocks.bs
    color_set = bs.map { |b| b.areas }.flatten.map { |a| a.c }.to_set
    debug("color_set size: #{color_set.size}")
    similarity = Hash(Tuple(Int32, Int32, RGB), Float64).new
    bs.each do |b|
      color_set.each do |c|
        similarity[{b.y, b.x, c}] = blocks.similarity_raw(@target, b, c)
      end
    end
    n = bs.size
    swap_cost = (OpSwap.cost * L * L / (bs[0].h * bs[0].w)).round.to_i
    n.times do
      best_cost = 0
      best_swap = {0, 0}
      n.times do |i|
        i.times do |j|
          diff = similarity[{bs[i].y, bs[i].x, bs[j].areas[0].c}]
          diff += similarity[{bs[j].y, bs[j].x, bs[i].areas[0].c}]
          diff -= similarity[{bs[i].y, bs[i].x, bs[i].areas[0].c}]
          diff -= similarity[{bs[j].y, bs[j].x, bs[j].areas[0].c}]
          cost = swap_cost + diff
          if cost < best_cost
            best_cost = cost
            best_swap = {i, j}
          end
        end
      end
      break if best_cost >= 0
      # TODO: wise swap
      blocks.swap(bs[best_swap[0]], bs[best_swap[1]])
    end
  end
end

def main
  solver = Solver.new(ARGV[0].to_i)
  ops = solver.solve
  while !ops[-1].is_a?(OpColor)
    ops.pop
  end
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
