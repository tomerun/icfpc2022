require "json"
require "stumpy_png"

PROBLEM_PATH = Path[ENV["PROBLEM"]? || "../problem"]
alias Pos = Tuple(Int32, Int32)

macro debug(msg)
  {% if flag?(:local) %}
    STDERR.puts({{msg}})
  {% end %}
end

macro debugf(format_string, *args)
  {% if flag?(:local) %}
    STDERR.printf({{format_string}}, {{*args}})
  {% end %}
end

def crash(msg, caller_line = __LINE__)
  STDERR.puts "[ERROR] line #{caller_line}: #{msg}"
  exit
end

macro assert(cond, msg = "", caller_line = __LINE__)
  {% if flag?(:local) %}
    if !({{cond}})
      crash({{msg}}, {{caller_line}})
    end
  {% end %}
end

alias RGB = Tuple(Int32, Int32, Int32)

def color_dist(c0, c1)
  return Math.sqrt((c0[0] - c1[0]) ** 2 + (c0[1] - c1[1]) ** 2 + (c0[2] - c1[2]) ** 2)
end

class Target
  getter :id, :h, :w, :pixel

  def initialize(@id : Int32)
    if @id >= 36
      OpLineCut.cost = 2
      OpPointCut.cost = 3
    end
    @h = @w = 0
    @pixel = [] of Array(RGB)
    File.open(PROBLEM_PATH.join(sprintf("%04d.txt", @id))) do |f|
      @h, @w = f.read_line.split.map(&.to_i)
      @pixel = Array.new(@h) do
        Array.new(@w, {0, 0, 0})
      end
      @h.times do |i|
        @w.times do |j|
          values = f.read_line.split.map(&.to_i)
          @pixel[@h - 1 - i][j] = RGB.from(values[0..2]) # upside down
        end
      end
    end
    @histos = Array(Array(Array(Array(Int32)))).new(3) { Array.new(@h + 1) { Array.new(@w + 1) { Array.new(256, 0) } } }
    3.times do |i|
      @h.times do |y|
        @w.times do |x|
          256.times do |j|
            @histos[i][y + 1][x + 1][j] = @histos[i][y][x + 1][j] + @histos[i][y + 1][x][j] - @histos[i][y][x][j]
          end
          @histos[i][y + 1][x + 1][@pixel[y][x][i]] += 1
        end
      end
    end
  end

  def best_color(bottom, left, top, right)
    cnt = (top - bottom) * (right - left)
    color = 3.times.map do |i|
      histo = @histos[i]
      sum = 0
      median = 0
      256.times do |j|
        sum += histo[top][right][j] - histo[top][left][j] - histo[bottom][right][j] + histo[bottom][left][j]
        if sum * 2 >= cnt
          median = j
          break
        end
      end
      median
    end.to_a
    return RGB.from(color)
  end

  def clustering(k)
  end
end

alias BlockId = Array(Int32)

def wrap_bracket(s)
  return "[#{s}]"
end

class OpLineCut
  @@cost = 7

  def initialize(@bid : BlockId, @is_vertical : Bool, @pos : Int32)
  end

  def to_s(io)
    io << "cut " << wrap_bracket(@bid.join(".")) << " " << wrap_bracket(@is_vertical ? "x" : "y") << " " << wrap_bracket(@pos)
  end

  def self.cost
    @@cost
  end

  def self.cost=(v)
    @@cost = v
  end
end

class OpPointCut
  @@cost = 10

  def initialize(@bid : BlockId, @y : Int32, @x : Int32)
  end

  def to_s(io)
    io << "cut " << wrap_bracket(@bid.join(".")) << " " << wrap_bracket("#{@x},#{@y}")
  end

  def self.cost
    @@cost
  end

  def self.cost=(v)
    @@cost = v
  end
end

class OpColor
  @@cost = 5

  def initialize(@bid : BlockId, @color : RGB)
  end

  def to_s(io)
    io << "color " << wrap_bracket(@bid.join(".")) << " " << wrap_bracket(@color.join(",") + ",255")
  end

  def self.cost
    @@cost
  end

  def self.cost=(v)
    @@cost = v
  end
end

class OpSwap
  @@cost = 3

  def initialize(@bid0 : BlockId, @bid1 : BlockId)
  end

  def to_s(io)
    io << "swap " << wrap_bracket(@bid0.join(".")) << " " << wrap_bracket(@bid1.join("."))
  end

  def self.cost
    @@cost
  end

  def self.cost=(v)
    @@cost = v
  end
end

class OpMerge
  @@cost = 1

  def initialize(@bid0 : BlockId, @bid1 : BlockId)
  end

  def to_s(io)
    io << "merge " << wrap_bracket(@bid0.join(".")) << " " << wrap_bracket(@bid1.join("."))
  end

  def self.cost
    @@cost
  end

  def self.cost=(v)
    @@cost = v
  end
end

alias Op = (OpLineCut | OpPointCut | OpColor | OpSwap | OpMerge)

class Area
  property :y, :x, :w, :h, :c

  def initialize(@y : Int32, @x : Int32, @h : Int32, @w : Int32, @c : RGB)
  end

  def top
    return @y + @h
  end

  def right
    return @x + @w
  end

  def to_s(io)
    io << "[#{@y}, #{@x}] - [#{top}, #{right}] #{@c}"
  end
end

class Block
  getter :id
  property :y, :x, :w, :h, :c, :idx, :areas

  def initialize(@y : Int32, @x : Int32, @h : Int32, @w : Int32, @id : BlockId, @idx : Int32)
    @areas = [] of Area
  end

  def top
    return @y + @h
  end

  def right
    return @x + @w
  end

  def s
    return @h * @w
  end

  def to_s(io)
    io << "#{@id.join(".")} [#{@y}, #{@x}] - [#{top}, #{right}] \n    " << @areas.join(", ")
  end
end

class Blocks
  getter :bs, :total_cost, :ops
  @h : Int32
  @w : Int32

  def initialize(target)
    @bs = [] of Block
    @ops = [] of Op
    @next_global_block_id = 1
    @total_cost = 0
    @h = target.h
    @w = target.w

    init_json = PROBLEM_PATH.join(sprintf("%04d.initial.json", target.id))
    if File.exists?(init_json)
      json = File.open(init_json) { |f| JSON.parse(f) }
      json["blocks"].as_a.each do |elem|
        bid = elem["blockId"].as_s.to_i
        @next_global_block_id = {@next_global_block_id, bid + 1}.max
        x = elem["bottomLeft"][0].as_i
        y = elem["bottomLeft"][1].as_i
        r = elem["topRight"][0].as_i
        t = elem["topRight"][1].as_i
        b = Block.new(y, x, t - y, r - x, [bid], @bs.size)
        color = elem["color"]?
        if color
          b.areas << Area.new(y, x, t - y, r - x, RGB.from(color.as_a.map { |v| v.as_i }.first(3)))
        else
          # dummy color
          b.areas << Area.new(y, x, t - y, r - x, {256, 256, 256})
        end
        @bs << b
      end
    else
      all = Block.new(0, 0, target.h, target.w, [0], 0)
      all.areas << Area.new(0, 0, target.h, target.w, {255, 255, 255})
      @bs << all
    end
  end

  private def detach(block)
    assert(0 <= block.idx && block.idx < @bs.size, block.idx)
    @bs[-1].idx = block.idx
    @bs[block.idx], @bs[-1] = @bs[-1], @bs[block.idx]
    block.idx = -1
    @bs.pop
  end

  def line_cut_vert(block, offset)
    assert(0 < offset)
    assert(offset < block.w)
    detach(block)
    pos = block.x + offset
    b0 = Block.new(block.y, block.x, block.h, offset, block.id + [0], @bs.size)
    b1 = Block.new(block.y, pos, block.h, block.w - offset, block.id + [1], @bs.size + 1)
    block.areas.each do |area|
      if area.right <= pos
        b0.areas << area
      elsif area.x >= pos
        b1.areas << area
      else
        b0.areas << Area.new(area.y, area.x, area.h, pos - area.x, area.c)
        b1.areas << Area.new(area.y, pos, area.h, area.right - pos, area.c)
      end
    end
    @bs << b0 << b1
    @ops << OpLineCut.new(block.id, true, pos)
    cost = (OpLineCut.cost * (@h * @w) / block.s).round.to_i
    debug("line_cut_vert cost:#{cost}")
    @total_cost += cost
    return b0, b1
  end

  def line_cut_horz(block, offset)
    assert(0 < offset)
    assert(offset < block.h)
    detach(block)
    pos = block.y + offset
    b0 = Block.new(block.y, block.x, offset, block.w, block.id + [0], @bs.size)
    b1 = Block.new(pos, block.x, block.h - offset, block.w, block.id + [1], @bs.size + 1)
    block.areas.each do |area|
      if area.top <= pos
        b0.areas << area
      elsif area.y >= pos
        b1.areas << area
      else
        b0.areas << Area.new(area.y, area.x, pos - area.y, area.w, area.c)
        b1.areas << Area.new(pos, area.x, area.top - pos, area.w, area.c)
      end
    end
    @bs << b0 << b1
    @ops << OpLineCut.new(block.id, false, pos)
    cost = (OpLineCut.cost * (@h * @w) / block.s).round.to_i
    debug("line_cut_horz cost:#{cost}")
    @total_cost += cost
    return b0, b1
  end

  def point_cut(block, offset_y, offset_x)
    assert(0 < offset_y)
    assert(offset_y < block.h)
    assert(0 < offset_x)
    assert(offset_x < block.w)
    detach(block)
    pos_y = block.y + offset_y
    pos_x = block.x + offset_x
    b0 = Block.new(block.y, block.x, offset_y, offset_x, block.id + [0], @bs.size)
    b1 = Block.new(block.y, pos_x, offset_y, block.w - offset_x, block.id + [1], @bs.size + 1)
    b2 = Block.new(pos_y, pos_x, block.h - offset_y, block.w - offset_x, block.id + [2], @bs.size + 2)
    b3 = Block.new(pos_y, block.x, block.h - offset_y, offset_x, block.id + [3], @bs.size + 3)
    block.areas.each do |area|
      if area.top <= pos_y
        if area.right <= pos_x
          b0.areas << area
        elsif area.x >= pos_x
          b1.areas << area
        else
          b0.areas << Area.new(area.y, area.x, area.h, pos_x - area.x, area.c)
          b1.areas << Area.new(area.y, pos_x, area.h, area.right - pos_x, area.c)
        end
      elsif area.y >= pos_y
        if area.right <= pos_x
          b3.areas << area
        elsif area.x >= pos_x
          b2.areas << area
        else
          b3.areas << Area.new(area.y, area.x, area.h, pos_x - area.x, area.c)
          b2.areas << Area.new(area.y, pos_x, area.h, area.right - pos_x, area.c)
        end
      else
        if area.right <= pos_x
          b0.areas << Area.new(area.y, area.x, pos_y - area.y, area.w, area.c)
          b3.areas << Area.new(pos_y, area.x, area.top - pos_y, area.w, area.c)
        elsif area.x >= pos_x
          b1.areas << Area.new(area.y, area.x, pos_y - area.y, area.w, area.c)
          b2.areas << Area.new(pos_y, area.x, area.top - pos_y, area.w, area.c)
        else
          b0.areas << Area.new(area.y, area.x, pos_y - area.y, pos_x - area.x, area.c)
          b1.areas << Area.new(area.y, pos_x, pos_y - area.y, area.right - pos_x, area.c)
          b2.areas << Area.new(pos_y, pos_x, area.top - pos_y, area.right - pos_x, area.c)
          b3.areas << Area.new(pos_y, area.x, area.top - pos_y, pos_x - area.x, area.c)
        end
      end
    end
    @bs << b0 << b1 << b2 << b3
    @ops << OpPointCut.new(block.id, pos_y, pos_x)
    cost = (OpPointCut.cost * (@h * @w) / block.s).round.to_i
    debug("point_cut     cost:#{cost}")
    @total_cost += cost
    return b0, b1, b2, b3
  end

  def color(block, color)
    block.areas.clear
    block.areas << Area.new(block.y, block.x, block.h, block.w, color)
    @ops << OpColor.new(block.id, color)
    cost = (OpColor.cost * (@h * @w) / block.s).round.to_i
    debug("color         cost:#{cost}")
    @total_cost += cost
    return block
  end

  def swap(block0, block1)
    assert(block0.h == block1.h && block0.w == block1.w, [block0, block1].join("\n"))
    assert(block0 != block1)
    my = block1.y - block0.y
    mx = block1.x - block0.x
    block0.y, block1.y = block1.y, block0.y
    block0.x, block1.x = block1.x, block0.x
    block0.areas.each do |a|
      a.y += my
      a.x += mx
    end
    block1.areas.each do |a|
      a.y -= my
      a.x -= mx
    end
    @ops << OpSwap.new(block0.id, block1.id)
    cost = (OpSwap.cost * (@h * @w) / block0.s).round.to_i
    debug("swap          cost:#{cost}")
    @total_cost += cost
    return block0, block1
  end

  def merge(block0, block1)
    assert(block0 != block1)
    detach(block0)
    detach(block1)
    is_simple_merge = block0.areas.size == 1 && block1.areas.size == 1 && block0.areas[0].c == block1.areas[0].c
    if block0.x == block1.x && block0.w == block1.w
      lo, hi = block0.y < block1.y ? {block0, block1} : {block1, block0}
      assert(lo.top == hi.y)
      block_new = Block.new(lo.y, lo.x, block0.h + block1.h, lo.w, [@next_global_block_id], @bs.size)
      if is_simple_merge
        block_new.areas << Area.new(lo.y, lo.x, block0.h + block1.h, lo.w, lo.areas[0].c)
      else
        # TODO: smart merge
        block_new.areas.concat(block0.areas)
        block_new.areas.concat(block1.areas)
      end
    elsif block0.y == block1.y && block0.h == block1.h
      left, right = block0.x < block1.x ? {block0, block1} : {block1, block0}
      assert(left.right == right.x)
      block_new = Block.new(block0.y, left.x, block0.h, block0.w + block1.w, [@next_global_block_id], @bs.size)
      if is_simple_merge
        block_new.areas << Area.new(left.y, left.x, left.h, block0.w + block1.w, left.areas[0].c)
      else
        # TODO: smart merge
        block_new.areas.concat(block0.areas)
        block_new.areas.concat(block1.areas)
      end
    else
      assert(false, [block0, block1])
      block_new = block0 # dummy
    end

    @bs << block_new
    @next_global_block_id += 1
    @ops << OpMerge.new(block0.id, block1.id)
    cost = (OpMerge.cost * (@h * @w) / {block0.s, block1.s}.max).round.to_i
    debug("merge         cost:#{cost}")
    @total_cost += cost
    return block_new
  end

  def output_ops(io)
    io << @ops.join("\n") << "\n"
  end

  def bitmap
    assert(@h == @bs.max_of { |b| b.top })
    assert(@w == @bs.max_of { |b| b.right })
    bm = Array.new(@h) { Array.new(@w, {0, 0, 0}) }
    @bs.each do |b|
      b.areas.each do |a|
        a.y.upto(a.top - 1) do |y|
          a.x.upto(a.right - 1) do |x|
            bm[y][x] = a.c
          end
        end
      end
    end
    return bm
  end

  def similarity(target)
    painted = bitmap()
    assert(target.h == painted.size)
    assert(target.w == painted[0].size)
    sum = 0.0
    target.h.times do |y|
      target.w.times do |x|
        dist = color_dist(target.pixel[y][x], painted[y][x])
        # if dist > 40.0
        #   debug([y, x, target.pixel[y][x], painted[y][x], dist])
        # end
        sum += dist
      end
    end
    alpha = 0.005
    return (sum * alpha).round.to_i
  end

  def similarity_raw(target, block, color)
    painted = bitmap()
    assert(target.h == painted.size)
    assert(target.w == painted[0].size)
    sum = 0.0
    block.areas.each do |a|
      a.y.upto(a.top - 1) do |y|
        a.x.upto(a.right - 1) do |x|
          dist = color_dist(target.pixel[y][x], color)
          sum += dist
        end
      end
    end
    return sum
  end

  def create_image(file_name)
    painted = bitmap()
    canvas = StumpyCore::Canvas.new(@w, @h)
    @h.times do |y|
      @w.times do |x|
        color = StumpyCore::RGBA.from_rgb(*painted[y][x])
        canvas[x, @h - 1 - y] = color
      end
    end
    StumpyPNG.write(canvas, file_name)
  end
end
