require 'pry'
require 'json'
require 'benchmark'

class Pai
  # attr_reader :suit, :number, :character

  class InvalidCharacterError < StandardError
  end

  # class CannotInitializeError < StandardError
  # end

  TILES = {
    "字" => %w(東 南 西 北 白 發 中),
    "萬" => %w(一 二 三 四 五 六 七 八 九),
    "筒" => %w(① ② ③ ④ ⑤ ⑥ ⑦ ⑧ ⑨),
    "索" => %w(1 2 3 4 5 6 7 8 9)
  }

  class << self
    def lookup_table
      @@lookup_table ||= TILES.each_with_object({}) do |(suit, characters), h|
        characters.each_with_index do |character, i|
          h[character] = { suit: suit, number: i + 1}
        end
      end
    end

    def convert_characters(characters)
      characters = characters.scan(/[^\s|,]/)
      characters.map { |c| convert_character(c) }
    end

    def convert_character(character)
      return character unless character.class == String
      pai = lookup_table[character]
      raise InvalidCharacterError unless pai
      pai
    end

    def to_characters(pais)
      pais.map { |pai| to_character(pai)}
    end

    def to_character(pai)
      TILES[pai[:suit]][pai[:number] - 1]
    end
  end
end

# class Group
#   attr_reader :kind, :suit, :number, :is_complete, :is_furou

#   def initialize(params)
#     @kind          = params[:kind] # 刻順槓嵌
#     @suit          = params[:suit]
#     @number        = params[:number]
#     @is_complete   = params[:is_complete]
#     @is_furou      = params[:is_furou] || false

#     @is_complete = true if @is_complete.nil?
#   end

#   def get_machi
#     return if is_complete

#     case kind
#     when "刻" then get_kotu_machi
#     when "順" then get_jun_machi
#     when "嵌" then get_kanchan_machi
#     end
#   end

#   def get_kotu_machi
#     [Pai.new(suit: suit, number: number)]
#   end

#   def get_jun_machi
#     before, after = number - 1, number + 2
#     machi = []
#     machi << Pai.new(suit: suit, number: before) if before >= 1
#     machi << Pai.new(suit: suit, number: after)  if after <= 9
#     machi
#   end

#   def get_kanchan_machi
#     [Pai.new(suit: suit, number: number + 1)]
#   end

#   class << self
#     def group_pais(pais: nil, suit: nil, numbers: nil, allow_incomplete: false, allow_kan: false)
#       unless suit && numbers
#         suits, numbers = pais.map(&:suit), pais.map(&:number)
#         return unless all_same?(suits)
#         suit = suits.first
#       end

#       num_of_pais = numbers.size
#       return unless num_of_pais.between?(2, 3) || (num_of_pais == 4 && allow_kan)

#       return group_same(suit, numbers.first, num_of_pais) if all_same?(numbers)

#       return unless suit != '字' && num_of_pais.between?(2, 3)
#       numbers = numbers.sort
#       return group_consecutive(suit, numbers.first, num_of_pais) if is_consecutive?(numbers)

#       return unless num_of_pais == 2 && is_kanchan?(numbers)
#       group_kanchan(suit, numbers.first)
#     end

#     def all_same?(arr)
#       arr.uniq.size == 1
#     end

#     def group_same(suit, number, num_of_pais)
#       case num_of_pais
#       when 4
#         Group.new(kind: "槓", suit: suit, number: number)
#       when 3
#         Group.new(kind: "刻", suit: suit, number: number)
#       when 2
#         Group.new(kind: "刻", suit: suit, number: number, is_complete: false)
#       else
#         nil
#       end
#     end

#     def is_consecutive?(numbers)
#       (0...numbers.size - 1).all? { |i| numbers[i] + 1 == numbers[i + 1] }
#     end

#     def group_consecutive(suit, number, num_of_pais)
#       case num_of_pais
#       when 3
#         Group.new(kind: "順", suit: suit, number: number)
#       when 2
#         Group.new(kind: "順", suit: suit, number: number, is_complete: false)
#       else
#         nil
#       end
#     end

#     def is_kanchan?(numbers)
#       a, b = numbers
#       a + 1 == b - 1
#     end

#     def group_kanchan(suit, number)
#       Group.new(kind: "嵌", suit: suit, number: number, is_complete: false)
#     end
#   end
# end

class NumGrouper
  FORMATIONS = [
    { symbol: "刻", category: "mentu",  method: :same },
    { symbol: "順", category: "mentu",  method: :sequence },
    { symbol: "対", category: "kouhou", method: :same },
    { symbol: "塔", category: "kouhou", method: :sequence },
    { symbol: "嵌", category: "kouhou", method: :kanchan },
  ]

  if File.exist?("cache.json")
    CACHE = JSON.parse(File.read("cache.json"))
  else
    CACHE = nil
  end

  class << self
    def initialize_tally
      {
        "mentu"    => [],
        "kouhou"   => [],
        "isolated" =>  [],
        "zyantou"  => false
      }
    end

    def group_from_cache(numbers)
      group(numbers, return_one: true)
    end

    def group(numbers, tally = initialize_tally, return_one: false) # sorted
      if return_one && CACHE
        cached_tally = CACHE[numbers.join("")]
        return combine_tallies(cached_tally, tally) if cached_tally
      end

      num_of_tiles = numbers.size
      return wrap(tally, return_one) if num_of_tiles.zero?

      first = numbers[0]
      return wrap(tally_with_category(tally, "isolated", first), return_one) if num_of_tiles == 1
      return group_without_first(first, numbers, tally, return_one) if first_is_isolated?(first, numbers)

      tallies = self.const_get("FORMATIONS").each_with_object([]) do |formation, arr|
        grouped = group_formation(formation, first, numbers, num_of_tiles, tally, return_one)
        arr << grouped if grouped
      end

      tallies << group_without_first(first, numbers, tally, return_one)

      tallies.flatten!
      tallies = remove_same(tallies)

      best_tally(tallies, return_one)
    end

    def wrap(tally, return_one)
      [tally] unless return_one
    end

    def combine_tallies(tally1, tally2)
      h = %w(mentu kouhou isolated).each_with_object({}) { |category, h| h[category] = tally1[category] + tally2[category] }
      h["zyantou"] = tally1["zyantou"] || tally2["zyantou"]
      h
    end

    def remove_same(tallies)
      set = tallies.inject({}) do |h, tally|
        h[get_key(tally)] = tally
        h
      end
      set.values
    end

    def get_key(tally)
      tally['mentu'].sort.join("") + tally['kouhou'].sort.join("")
    end

    def group_without_first(first, numbers, tally, return_one)
      group(numbers[1..-1], tally_with_category(tally, "isolated", first), return_one: return_one)
    end

    def group_formation(formation, first, numbers, num_of_tiles, tally, return_one)
      symbol       = formation[:symbol]
      category     = formation[:category]
      num_to_group = get_num_to_group(category)
      method       = formation[:method]

      grouped, remaining = send("group_#{method}", first, numbers, num_of_tiles, num_to_group)
      group(remaining, tally_with_category(tally, category, "#{symbol}#{first}", symbol == "対"), return_one: return_one) if grouped
    end

    def get_num_to_group(category)
      category == "mentu" ? 3 : 2
    end

    def first_is_isolated?(first, numbers)
      numbers[1] - first > 2
    end

    def group_same(first, numbers, num_of_tiles, num_of_same_tiles)
      return if num_of_tiles < num_of_same_tiles
      return unless (1...num_of_same_tiles).all? { |i| first == numbers[i] }
      [numbers[0...num_of_same_tiles], numbers[num_of_same_tiles..-1]]
    end

    def group_sequence(first, numbers, num_of_tiles, length_of_sequence)
      return if num_of_tiles < length_of_sequence || first >=  11 - length_of_sequence
      return unless (1...length_of_sequence).all? { |i| numbers.include?(first + i) }
      sequence = (first...first + length_of_sequence).to_a
      [sequence, get_remaining(numbers, sequence)]
    end

    def group_kanchan(first, numbers, num_of_tiles, _)
      return if first >= 8
      return unless numbers.include?(first + 2)
      kanchan = [first, first + 2]
      [kanchan, get_remaining(numbers, kanchan)]
    end

    def tally_with_category(tally, category, group, zyantou = false)
      tally = tally_copy(tally)
      tally[category] << group
      tally["zyantou"] = true if zyantou
      tally
    end

    def get_remaining(numbers, to_remove)
      numbers = numbers.clone
      to_remove.each { |i| numbers.delete_at(numbers.index(i)) }
      numbers
    end

    def tally_copy(tally)
      copy = {}
      tally.each do |k ,v|
        copy[k] = v.clone
      end
      copy
    end

    def best_tally(tallies, return_one)
      mentu_count = tallies.map { |t| t['mentu'].count }
      max_mentu = mentu_count.max
      indices_with_max_mentu = (0...mentu_count.size).select { |i| mentu_count[i] == max_mentu }
      tallies = indices_with_max_mentu.map{ |i| tallies[i] }

      if tallies.count > 1
        isolated_count = tallies.map { |t| t['isolated'].count }
        min_isolated = isolated_count.min
        indices_with_min_isolated = (0...isolated_count.size).select { |i| isolated_count[i] == min_isolated }
        tallies = indices_with_min_isolated.map{ |i| tallies[i] }
      end

      return_one ? tallies.first : tallies
    end
  end
end

class ZihaiGrouper < NumGrouper
  FORMATIONS = [
    { symbol: "刻", category: "mentu",  method: :same },
    { symbol: "対", category: "kouhou", method: :same },
  ]
end

class FurouIdentifier
  class InvalidKanError < StandardError
  end

  class InvalidFurouError < StandardError
  end

  def self.identify(pais, ankan: false)
    numbers, suits = pais.map { |p| p[:number] }, pais.map { |p| p[:suit] }
    raise InvalidFurouError if suits.uniq.size != 1
    suit = suits.first

    if numbers.size == 4 && numbers.uniq.size == 1
      formation = ankan ? "暗槓#{numbers.first}" : "大明槓#{numbers.first}"
      return { suit: suit, formation: formation }
    else
      raise InvalidKanError if ankan
    end

    grouper = suit == "字" ? ZihaiGrouper : NumGrouper
    tally = grouper.group(numbers, return_one: true)
    raise InvalidFurouError if tally['mentu'].empty? || tally['kouhou'].any? || tally['isolated'].any?
    formation = tally['mentu'].first
    { suit: suit, formation: formation }
  end

  def self.string_into_formation(furou_characters)
    ankan_marker = furou_characters.slice!('*')
    furou_characters = Pai.convert_characters(furou_characters)
    FurouIdentifier.identify(furou_characters, ankan: !!ankan_marker)
  end
end

class MonzenGrouper
  class << self
    def group(pais, return_one: true)
      tallies_per_suit = separated_pais(pais).map do |suit, numbers|
        grouper = suit == "字" ? ZihaiGrouper : NumGrouper
        tallies = grouper.group(numbers, return_one: return_one)
        tallies = [tallies] if return_one # force to array since return_one setting returns a non-array
        tallies.map { |tally| add_suit_to_tally(suit, tally) }
      end
      possibilities = get_permutations(tallies_per_suit)
      possibilities.map { |p| combine_suits(p) }
    end

    def separated_pais(pais)
      hash = pais.inject({}) do |h, pai|
        suit, number = pai[:suit], pai[:number]
        h[suit] ||= []
        h[suit] << number
        h
      end
      hash.each { |k,v| v.sort! }
      hash
    end

    def add_suit_to_tally(suit, tally)
      new_tally = {}
      new_tally['mentu']    = tally['mentu'].map { |mentu| { suit: suit, formation: mentu} }
      new_tally['kouhou']   = tally['kouhou'].map { |kouhou| { suit: suit, formation: kouhou} }
      new_tally['isolated'] = tally['isolated'].map { |number| { suit: suit, number: number } }
      new_tally['zyantou']  = tally['zyantou']
      new_tally
    end

    def get_permutations(tallies)
      permutations(tallies).flatten(tallies.size - 1)
    end

    def permutations(tallies, stored = [])
      return stored if tallies.empty?
      first_suit, rest = tallies[0], tallies[1..-1]
      all = first_suit.map do |tally|
        new_record = stored.dup
        new_record << tally
        permutations(rest, new_record)
      end
    end

    def combine_suits(tallies)
      combined_tally = {}
      %w(mentu kouhou isolated).each do |type|
        combined_tally[type] = tallies.inject([]) { |arr, t| arr += t[type] }
      end
      combined_tally['zyantou'] = tallies.inject(false) { |bool, t| bool || t['zyantou'] }
      combined_tally
    end
  end
end

class CacheGenerator
  class << self
    def combinations(max_repeat: 3, max_tiles: 5, start_from: 1, up_to: 9, existing: [])
      return existing if max_tiles == 0

      start_from += 1 if existing[-max_repeat] == start_from

      arr = []
      (start_from..up_to).each do |i|
        before = existing.clone
        before << i
        arr << combinations(max_repeat: max_repeat, max_tiles: max_tiles - 1, start_from: i, up_to: up_to, existing: before)
      end

      arr
    end

    def get_combinations(max_repeat: 4, max_tiles: 12, start_from: 1, up_to: 9)
      combinations(
        max_repeat: max_repeat,
        max_tiles:  max_tiles,
        start_from: start_from,
        up_to:      up_to
      ).flatten(max_tiles - 1)
    end

    def get_all_combinations(max_repeat: 4, min_tiles: 1, max_tiles: 9, start_from: 1, up_to: 9)
      (min_tiles..max_tiles).each_with_object([]) do |i, arr|
        arr << get_combinations(max_repeat: max_repeat, max_tiles: i, start_from: start_from, up_to: up_to)
      end.flatten(1)
    end

    def generate_cache(combinations = get_all_combinations, file = "cache.json")
      hash = {}
      combinations.each do |numbers|
        value = NumGrouper.group(numbers, return_one: true)
        key = numbers.join("")
        hash[key] = value
      end
      File.open(file, 'a+') { |f| f.write(hash.to_json) }
    end
  end
end

class GeneralGrouper
  attr_reader :menzen, :furou, :return_one, :shantei, :formations

  def initialize(menzen: , furou: [], return_one: true)
    @menzen = as_pais(menzen)
    @furou = furou
    @return_one = return_one
    @shantei = nil
    @formations = nil
  end

  def as_pais(menzen)
    menzen.map { |m| as_pai(m) }
  end

  def as_pai(input)
    return input if input.class == Hash
    Pai.convert_character(input)
  end

  def run
    scores = tallies.map { |t| get_shantei_from_tally(t) }
    @shantei = min_score = scores.min

    indices_with_min_score = (0...scores.size).select { |i| scores[i] == min_score }
    best = indices_with_min_score.map{ |i| tallies[i] }
    @formations = return_one ? best.first : best

    { shantei: @shantei, formations: @formations }
  end

  def tallies
    return @tallies if @tallies

    tallies = MonzenGrouper.group(menzen, return_one: return_one)
    tallies.each { |tally| tally['mentu'] += furou }
    @tallies = tallies
  end

  def get_shantei_from_tally(tally)
    mentu, kouhou, zyantou = tally["mentu"].size, tally["kouhou"].size, tally["zyantou"] ? 1 : 0
    8 - 2 * mentu - [4 - mentu, kouhou - zyantou].min - zyantou
  end
end

class KokuShiMuSouGrouper
  KOKUSHI_CHARACTERS = %w(東 南 西 北 白 發 中 一 九 ① ⑨ 1 9)

  attr_reader :shantei, :machi, :unmatched_menzen, :matched_kokushi_characters

  def initialize(menzen:)
    @unmatched_menzen = menzen.map { |c| c.dup }
    @matched_kokushi_characters = []
    @shantei = nil
    @machi = nil
  end

  def run
    # first pass
    KOKUSHI_CHARACTERS.each do |kokushi_char|
      match_kokushi_char(kokushi_char)
    end

    # second pass
    has_zyantou = KOKUSHI_CHARACTERS.find do |kokushi_char|
      match_kokushi_char(kokushi_char)
    end

    @machi = KOKUSHI_CHARACTERS - matched_kokushi_characters
    unless has_zyantou
      @machi << '?'
    end

    @shantei = @machi.count - 1
  end

  def match_kokushi_char(kokushi_char)
    index = unmatched_menzen.index(kokushi_char)
    return unless index
    unmatched_menzen.delete_at(index)
    matched_kokushi_characters << kokushi_char
  end
end

class ChiToiTuGrouper
  attr_accessor :menzen, :shantei, :machi

  def initialize(menzen:)
    @menzen = menzen
    @shantei = nil
    @machi = nil
  end

  def run
    paired, isolated = histogram.partition { |char, count| count >= 2 }
    @shantei = 6 - paired.count
    @machi = isolated.map(&:first)
  end

  def histogram
    @histogram ||= menzen.inject({}) do |h, char|
      h[char] = (h[char] || 0) + 1
      h
    end
  end
end

module RegularizeHelper
  def as_array(menzen)
    return menzen if menzen.class == Array
    menzen.scan(/[^\s|,]/)
  end

  def as_formations(array)
    array.map { |group| as_formation(group) }
  end

  def as_formation(group)
    return group if group.class == Hash
    FurouIdentifier.string_into_formation(group)
  end

  def into_number(input)
    return input if input.class == Integer
    Pai.convert_character(input)[:number]
  end
end

class ShanteiCalculator
  include RegularizeHelper

  attr_reader :menzen, :furou, :general_grouper,
    :kokushi_grouper, :chitoitu_grouper, :groupers, :shantei, :quick_find

  class WrongNumberOfPaisError < StandardError; end

  def initialize(menzen:, furou: [], quick_find: true)
    @menzen = as_array(menzen)
    @furou = as_formations(furou)
    @quick_find = quick_find
  end

  def run
    validate_pai_count

    @general_grouper = GeneralGrouper.new(menzen: menzen, furou: @furou, return_one: quick_find)
    if furou.empty?
      @kokushi_grouper = KokuShiMuSouGrouper.new(menzen: menzen)
      @chitoitu_grouper = ChiToiTuGrouper.new(menzen: menzen)
    end
    @groupers = [@general_grouper, @kokushi_grouper, @chitoitu_grouper].compact
    groupers.each { |grouper| grouper.run }

    @shantei = groupers.map{ |g| g.shantei }.min
  end

  def validate_pai_count
    raise WrongNumberOfPaisError unless menzen.size / 3 + furou.size == 4 && menzen.size % 3 != 0
  end
end

class YakuIdentifier
  include RegularizeHelper

  attr_reader :menzen, :furou, :agari_hai, :tumo, :richi, :double_richi, :ipatu,
    :rinshan, :chankan, :first_jun, :last_hai, :dora_count, :aka_dora_count, :oya, :chanfon, :menfon, :yaku, :yakuman_yaku, :formations, :shantei_calc

  class WrongNumberOfPaisError < StandardError; end
  class InvalidSituation < StandardError; end
  class NotAgariError < StandardError; end

  ZIHAI = %w(_ 東 南 西 北 白 發 中)

  # menzen arg must include the agari_hai in it as well
  def initialize(
    menzen:,
    agari_hai:,
    furou: [],
    tumo: false,
    richi: false,
    double_richi: false,
    ipatu: false,
    rinshan: false,
    chankan: false,
    first_jun: false,
    last_hai: false,
    dora_count: 0,
    aka_dora_count: 0,
    oya: false,
    chanfon: 1,
    menfon: 1
    )
    @menzen         = as_array(menzen)
    @furou          = as_formations(furou)
    @agari_hai      = agari_hai
    @richi          = double_richi || richi
    @double_richi   = double_richi
    @ipatu          = ipatu
    @tumo           = tumo
    @rinshan        = rinshan
    @chankan        = chankan
    @last_hai       = last_hai
    @dora_count     = dora_count
    @aka_dora_count = aka_dora_count
    @oya            = oya
    @chanfon        = into_number(chanfon)
    @menfon         = into_number(menfon)
    @yaku           = []
    @yakuman_yaku   = []
  end

  def run
    validate

    first_jun_tumo?
    return calculate if kokushi?

    get_general_yaku
    tanyao?
    iisou?
    return calculate if chitoitu?

    yakuhai_yakuman_and_associated?
    return calculate if yakuman_yaku.any? # wrong: need to check suuankou first

    get_yaku_hai
    get_menzenchin_yaku
  end

  def validate
    raise InvalidSituation if rinshan && chankan
    raise InvalidSituation if rinshan && !tumo
    raise InvalidSituation if (richi || ipatu) && !is_menzenchin?
    raise InvalidSituation if !richi && ipatu
    validate_agari
  end


  def is_menzenchin?
    @is_menzenchin ||= @furou.empty? || @furou.all? { |f| is_ankan?(f) }
  end

  def is_ankan?(furou)
    furou[:formation][0..1] == "暗槓"
  end

  def validate_agari
    @shantei_calc = ShanteiCalculator.new(
      menzen: menzen + [agari_hai],
      furou: furou,
      quick_find: false
    )
    shantei_calc.run
    raise NotAgariError unless shantei_calc.shantei == -1
  end

  def first_jun_tumo?
    return unless first_jun && tumo
    if oya
      @yakuman_yaku << "天和"
    else
      @yakuman_yaku << "地和"
    end
  end

  def kokushi?
    return unless shantei_calc.kokushi_grouper&.shantei == -1
    @yakuman_yaku << "国士無双"
  end

  def chitoitu?
    return unless shantei_calc.chitoitu_grouper&.shantei == -1 &&
      shantei_calc.general_grouper.shantei != -1
    @yaku << "七対子"
  end

  def get_general_yaku
    @yaku << "立直" if richi && !double_richi
    @yaku << "W立直" if double_richi
    @yaku << "一発" if ipatu
    @yaku << "嶺上開花" if rinshan
    @yaku << "搶槓" if chankan
    @yaku << "門前清自摸和" if is_menzenchin? && tumo
    @yaku << "海底摸月" if last_hai && tumo
    @yaku << "河底撈魚" if last_hai && !tumo
  end

  def formations
    @formations ||= shantei_calc.general_grouper.formations.map { |f| format_formation(f) }
  end

  def format_formation(formation)
    {
      mentu: formation['mentu'].map { |h| split_formation(h) },
      zyantou: formation['kouhou'].map { |h| split_formation(h) }.first
    }
  end

  def split_formation(h)
    f = h[:formation]
    {
      suit: h[:suit],
      type: f[0..-2],
      number: f[-1].to_i
    }
  end

  def _formation
    @_formation ||= formations.first
  end

  def _mentu
    @_mentu ||= _formation[:mentu]
  end

  def _zyantou
    @_zyantou ||= _formation[:zyantou]
  end

  def all_suits
    @all_suits ||= hais.map{ |h| h[:suit] }.uniq
  end

  def hais
    @hais ||= shantei_calc.general_grouper.menzen
  end

  def tanyao?
    return if all_suits.any? { |s| s == '字' } ||
      (hais.map { |h| h[:number] } & [1, 9]).any?

    @yaku << "断么九"
  end

  def iisou?
    return if all_suits.count > 2

    if all_suits.count == 2
      return unless all_suits.include?('字')
      @yaku << '混一色'
    else
      only_suit = all_suits.first
      if only_suit == '字'
        @yakuman_yaku << '字一色'
      else
        @yaku << "清一色"
        chuurenboutou?
      end
    end

    rouiisou?
  end

  def rouiisou?
    return unless all_suits.include?("索")
    uniq_hais = hais.uniq.map{ |hai| Pai.to_character(hai) }
    return unless (uniq_hais - %w(2 3 4 6 8 発)).empty?
    @yakuman_yaku << "緑一色"
  end

  # WRONG: should check 13 + 1
  def chuurenboutou?
    return unless is_menzenchin?
    return unless hais.map{ |h| h[:number] }.sort.join("") == "1112345678999"
    @yakuman_yaku << "九蓮宝燈"
  end

  def yakuhai_yakuman_and_associated?
    numbers = _mentu.select { |g| g[:suit] == '字' }.map { |g| g[:number] }
    return true if suusii?(numbers) || sangen?(numbers)
    return unless _zyantou[:suit] == '字'

    numbers << _zyantou[:number]
    suusii?(numbers, with_zyantou: true)
    sangen?(numbers, with_zyantou: true)
  end

  def suusii?(numbers, with_zyantou: false)
    return unless (numbers & [1, 2, 3, 4]).count == 4
    if with_zyantou
      @yakuman_yaku << "小四喜"
    else
      @yakuman_yaku << "大四喜"
    end
  end

  def sangen?(numbers, with_zyantou: false)
    return unless (numbers & [5, 6, 7]).count == 3
    if with_zyantou
      @yaku << "小三元"
    else
      @yakuman_yaku << "大三元"
    end
  end

  def get_yaku_hai
    _mentu.each do |group|
      @yaku << "役牌　#{ZIHAI[group[:number]]}" if yaku_hai?(group)
    end
  end

  def yaku_hai?(group)
    return false unless group[:suit] == '字'
    [5,6,7, chanfon, menfon].include?(group[:number])
  end


  def get_menzenchin_yaku
    return unless is_menzenchin?
    # suuankou
    # iipeikou
    # ryanpeikou
    # pinfu
  end

  def calculate
    # to be implemented
  end
end

binding.pry

# samples = CacheGenerator.get_combinations(max_tiles: 14).sample(10)
# samples.each {|s| p s; puts "\n"; pp GeneralGrouper.group(menzen: s.join(""), furou: [], return_one: false); puts "\n\n\n" }
