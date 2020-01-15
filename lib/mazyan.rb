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
          h[character] = { suit: suit, number: i + 1, character: character }
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

  # if File.exist?("cache.json")
  #   CACHE = JSON.parse(File.read("cache.json"))
  # else
  #   CACHE = nil
  # end
  CACHE = nil

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

    # this whole method should be an instance method, so return_one does not have to be passed in over and over
    def group(numbers, tally = initialize_tally, return_one: false) # sorted
      if return_one && CACHE
        cached_tally = CACHE[numbers.join("")]
        return combine_tallies(cached_tally, tally) if cached_tally
      end

      num_of_tiles = numbers.size
      return wrap(tally, return_one) if num_of_tiles.zero?

      first = numbers[0]
      return wrap(tally_isolated(tally, first), return_one) if num_of_tiles == 1
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
      return tally if return_one
      [tally]
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
      tally['mentu'].map{ |h| "#{h[:type]}#{h[:number]}" }.sort.join("") +
        tally['kouhou'].map{ |h| "#{h[:type]}#{h[:number]}" }.sort.join("")
    end

    def group_without_first(first, numbers, tally, return_one)
      group(numbers[1..-1], tally_isolated(tally, first), return_one: return_one)
    end

    def group_formation(formation, first, numbers, num_of_tiles, tally, return_one)
      symbol       = formation[:symbol]
      category     = formation[:category]
      num_to_group = get_num_to_group(category)
      method       = formation[:method]

      grouped, remaining = send("group_#{method}", first, numbers, num_of_tiles, num_to_group)
      group(remaining, tally_with_category_new(tally, category, symbol, first, symbol == "対"), return_one: return_one) if grouped
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

    def tally_isolated(tally, number)
      tally = tally_copy(tally)
      tally["isolated"] << number
      tally
    end

    def tally_with_category_new(tally, category, symbol, number, zyantou = false)
      tally = tally_copy(tally)
      tally[category] << { type: symbol, number: number }
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

    # if return one foramtion only, then should return ones with the highest mentu count; BUT this is not ideal when wanting return all formations, e.g. [1,1,1,2,3,4,5,6,7,8,9,9,9] should return 9+ formations but this implementation returns only 3
    def best_tally_for_one(tallies)
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

      tallies.first
    end

    def best_tally(tallies, return_one)
      return best_tally_for_one(tallies) if return_one

      scores = tallies.map { |t| get_score(t) }
      best_score = scores.min
      indices_with_best_score = (0...scores.size).select { |i| scores[i] == best_score }
      tallies = indices_with_best_score.map{ |i| tallies[i] }
    end

    def get_score(tally)
      mentu, kouhou, zyantou = tally["mentu"].size, tally["kouhou"].size, tally["zyantou"] ? 1 : 0
      hai_count = 3 * mentu + 2 * kouhou + tally['isolated'].size
      max_mentu_count = hai_count / 3
      8 - 2 * mentu - [max_mentu_count - mentu, kouhou - zyantou].min - zyantou
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

  def self.identify(hais, ankan: false)
    numbers, suits = hais.map { |p| p[:number] }, hais.map { |p| p[:suit] }
    raise InvalidFurouError if suits.uniq.size != 1
    suit = suits.first

    if numbers.size == 4 && numbers.uniq.size == 1
      type = ankan ? "暗槓" : "大明槓"
      return { suit: suit, type: type, number: numbers.first, hais: hais }
    else
      raise InvalidKanError if ankan
    end

    grouper = suit == "字" ? ZihaiGrouper : NumGrouper
    tally = grouper.group(numbers, return_one: true)
    raise InvalidFurouError if tally['mentu'].empty? || tally['kouhou'].any? || tally['isolated'].any?
    formation = tally['mentu'].first
    formation.merge(suit: suit, hais: hais)
  end

  def self.string_into_formation(furou_characters)
    ankan_marker = furou_characters.slice!('*')
    furou_hais = Pai.convert_characters(furou_characters)
    FurouIdentifier.identify(furou_hais, ankan: !!ankan_marker)
  end
end

class MenzenGrouper
  # should be instance method
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
      new_tally['mentu']    = tally['mentu'].map { |mentu| mentu.merge(suit: suit) }
      new_tally['kouhou']   = tally['kouhou'].map { |kouhou| kouhou.merge(suit: suit) }
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
    @menzen = menzen # accept hais only
    @furou = furou
    @return_one = return_one
    @shantei = nil
    @formations = nil
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

    tallies = MenzenGrouper.group(menzen, return_one: return_one)
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

  attr_reader :shantei, :machi, :unmatched_characters, :matched_kokushi_characters

  def initialize(menzen:)
    @menzen = menzen # accept hais only

    @unmatched_characters = menzen.map { |h| h[:character] }
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
    index = unmatched_characters.index(kokushi_char)
    return unless index
    unmatched_characters.delete_at(index)
    matched_kokushi_characters << kokushi_char
  end
end

class ChiToiTuGrouper
  attr_accessor :menzen, :characters, :shantei, :machi

  def initialize(menzen:)
    @menzen = menzen # accept hais only

    @characters = menzen.map { |h| h[:character] }
    @shantei = nil
    @machi = nil
  end

  def run
    paired, isolated = histogram.partition { |char, count| count >= 2 }
    @shantei = 6 - paired.count
    @machi = isolated.map(&:first)
  end

  def histogram
    @histogram ||= characters.inject({}) do |h, char|
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

  def as_pais(menzen)
    menzen.map { |m| as_pai(m) }
  end

  def as_pai(input)
    return input if input.class == Hash
    Pai.convert_character(input)
  end
end

class ShanteiCalculator
  include RegularizeHelper

  attr_reader :menzen, :furou, :general_grouper,
    :kokushi_grouper, :chitoitu_grouper, :groupers, :shantei, :quick_find, :shantei

  class WrongNumberOfPaisError < StandardError; end

  def initialize(menzen:, furou: [], quick_find: true)
    @menzen = as_pais(as_array(menzen)) # consider only accept hais
    @furou = as_formations(furou)
    @quick_find = quick_find
  end

  def run
    validate_pai_count

    @general_grouper = GeneralGrouper.new(menzen: menzen, furou: furou, return_one: quick_find)
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

require 'forwardable'
class YakuIdentifier
  extend Forwardable
  include RegularizeHelper

  attr_reader :menzen, :furou, :machi, :tumo, :richi, :double_richi, :ipatu,
    :rinshan, :chankan, :first_jun, :last_hai, :dora_count, :aka_dora_count, :oya, :chanfon, :zifon,
    :yaku, :yakuman_yaku, :formations,
    :hais, :zi_hais, :number_hais, :numbers, :all_suits

  delegate [:shantei, :general_grouper, :kokushi_grouper, :chitoitu_grouper] => :shantei_calc
  delegate [:formations] => :general_grouper

  class WrongNumberOfPaisError < StandardError; end
  class InvalidSituation < StandardError; end
  class NotAgariError < StandardError; end

  ZIHAI = %w(東 南 西 北 白 發 中)
  ROUIUSOU_HAIS = %w(2 3 4 6 8 發)

  # menzen arg must include the machi in it as well
  def initialize(
    menzen:,
    machi:,
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
    zifon: 1
    )
    @menzen         = as_pais(as_array(menzen))
    @furou          = as_formations(furou)
    @machi          = as_pai(machi)

    @richi          = double_richi || richi
    @double_richi   = double_richi
    @ipatu          = ipatu
    @tumo           = tumo

    # I feel the following 5 can be part of an options hash
    @rinshan        = rinshan
    @chankan        = chankan
    @last_hai       = last_hai # haitei
    @dora_count     = dora_count # should instead provide the ora hyouzihais
    @aka_dora_count = aka_dora_count # should instead refer to the hais id, if available

    @chanfon        = into_number(chanfon)
    @zifon          = into_number(zifon)
    @oya            = zifon == 1
    @yaku           = []
    @yakuman_yaku   = []
  end

  def run
    prepare_helpers

    validate

    # return calculate if kokushi?

    # # note: since chitoitu does not have formation, the following methods cannot expect a formation
    # get_general_yaku
    # tanyao?
    # routou_yaku?
    # iisou?
    # return calculate if chitoitu? # WRONG: chitoitu can also have honchuntaiyaokyuu yaku

    # rouiisou?
    # chuurenboutou?
    # yakuhai_yakuman_and_associated?
    # get_yaku_hai

    # formations.each do |formation| # for testing only; to fix
    #   ankou_yaku?(formation)
    #   chantaiyaokyuu_yaku?(formation)
    #   get_menzenchin_yaku(formation)
    # end

    # get_yaku
  end

  def prepare_helpers
    @hais = (@menzen + @furou.map { |f| f[:hais] }).flatten + [@machi]
    @zi_hais, @number_hais = @hais.partition { |hai| hai[:suit] == '字' }
    @numbers = number_hais.map { |hai| hai[:number] }
    @all_suits = hais.map{ |h| h[:suit] }.uniq
  end

  def validate
    raise InvalidSituation if rinshan && chankan
    raise InvalidSituation if chankan && tumo
    raise InvalidSituation if rinshan && !tumo
    raise InvalidSituation if (richi || ipatu) && !is_menzenchin?
    raise InvalidSituation if !richi && ipatu

    shantei_calc.run
    raise NotAgariError unless shantei == -1
  end

  def shantei_calc
    @shantei_calc ||= ShanteiCalculator.new(
      menzen: menzen + [machi],
      furou: furou,
      quick_find: false
    )
  end

  # I feel all of this logic can be moved into a separate class for detemining the yaku
  # especailly this could be removed from YakuIdentifier, and instead use a separate logic to check
  # def first_jun_tumo?
  #   return unless first_jun && tumo
  #   if oya
  #     @yakuman_yaku << "天和"
  #   else
  #     @yakuman_yaku << "地和" # Note: 第1ツモの前に他家によるチー・ポン・カンが入ると無効になる
  #   end
  # end

  YAKU_RULES = [
    { name: "国士無双", requirements: [:is_menzenchin?, :is_kokushi] },
    { name: "七対子", requirements: [:is_menzenchin?, :is_chitoitu] }, # or exclusive with ryanpeikou
    { name: "W立直", requirements: [:is_menzenchin?, :double_richi] },
    { name: "立直", requirements: [:is_menzenchin?, :richi], mutually_exclusive: ["W立直"] },
    { name: "一発", requirements: [:is_menzenchin?, :richi, :ipatu] },
    { name: "嶺上開花", requirements: [:rinshan] },
    { name: "搶槓", requirements: [:chankan] },
    { name: "門前清自摸和", requirements: [:is_menzenchin?, :tumo] },
    { name: "海底摸月", requirements: [:last_hai, :tumo] },
    { name: "河底撈魚", requirements: [:last_hai], mutually_exclusive: ["海底摸月"] },
    { name: "断么九", requirements: [:no_yaokyu] },
    { name: "清老頭", requirements: [:only_yaokyu, :no_zi_hais] },
    { name: "混老頭", requirements: [:only_yaokyu], mutually_exclusive: ["清老頭"] },
    { name: "字一色", requirements: [:no_number_hais] },
    { name: "清一色", requirements: [:same_suit_numbers, :no_zi_hais] },
    { name: "混一色", requirements: [:same_suit_numbers], mutually_exclusive: ["清一色"] },
    { name: "大四喜", requirements: [:has_three_東, :has_three_南, :has_three_西, :has_three_北] },
    { name: "小四喜", requirements: [:has_two_東, :has_two_南, :has_two_西, :has_two_北], mutually_exclusive: ["大四喜", "七対子"] },# hacky, another way is to split this into 4 rules; or to write a dedicated method for this
    { name: "大三元", requirements: [:has_three_白, :has_three_發, :has_three_中] },
    { name: "小三元", requirements: [:has_two_白, :has_two_發, :has_two_中], mutually_exclusive: ["大三元", "七対子"] },
    { name: "役牌 白", requirements: [:has_three_白] },
    { name: "役牌 發", requirements: [:has_three_發] },
    { name: "役牌 中", requirements: [:has_three_中] },
    { name: "場風", requirements: [:is_chanfon] },
    { name: "自風", requirements: [:is_zifon] },
    { name: "純正九蓮宝燈", requirements: [:is_menzenchin?, :no_zi_hais, :same_suit_numbers, :jun_sei_chuu_ren_bou_tou?]},
    { name: "九蓮宝燈", requirements: [:is_menzenchin?, :no_zi_hais, :same_suit_numbers, :chuu_ren_bou_tou?], mutually_exclusive: ["純正九蓮宝燈"]},
    { name: "緑一色", requirements: [:rou_ii_sou?] }

  ]

  def get_yaku
    genereate_yaku_hai_methods

    yaku = []
    YAKU_RULES.each do |rule|
      next if rule[:mutually_exclusive] && (yaku & rule[:mutually_exclusive]).any?
      next unless rule[:requirements].all? { |req| send(req) }
      yaku << rule[:name]
    end
    yaku
  end

  def is_menzenchin?
    @is_menzenchin ||= @furou.all? { |f| f[:type] == "暗槓" } # this includes @furou.empty?
  end

  def is_kokushi
    kokushi_grouper&.shantei == -1
  end

  def is_chitoitu
    chitoitu_grouper&.shantei == -1 &&
      general_grouper.shantei != -1 # or else ryanpeikou
  end

  def no_yaokyu
    @no_yaokyu ||= (numbers & [1, 9]).empty?
  end

  def only_yaokyu
    @only_yaokyu ||= (numbers - [1, 9]).empty?
  end

  def no_zi_hais
    zi_hais.empty?
  end

  def no_number_hais
    number_hais.empty?
  end

  def same_suit_numbers
    @same_suit_numbers ||= number_hais.map{|h| h[:suit]}.uniq.count <= 1
  end

  def genereate_yaku_hai_methods
    ZIHAI.each do |zihai|
      instance_eval <<EOS
        def has_three_#{zihai}
          zi_hais_tally["#{zihai}"] >= 3
        end

        def has_two_#{zihai}
          zi_hais_tally["#{zihai}"] >= 2
        end
EOS
    end
  end

  def zi_hais_tally
    @zi_hais_tally ||= ZIHAI.inject({}) { |h, hai| h.tap { h[hai] = 0 } }.tap do |h|
      zi_hais.each do |hai|
        h[hai[:character]] += 1
      end
    end
  end

  def is_chanfon
    send "has_three_#{ZIHAI[chanfon]}"
  end

  def is_zifon
    send "has_three_#{ZIHAI[zifon]}"
  end

  def rou_ii_sou?
    (hais.map { |h| h[:character] } - ROUIUSOU_HAIS).empty?
  end

  def jun_sei_chuu_ren_bou_tou?
    chuu_ren_bou_tou? &&
      chuu_ren_bou_tou_tally.first == machi[:number]
  end

  def chuu_ren_bou_tou?
    !!chuu_ren_bou_tou_tally
  end

  def chuu_ren_bou_tou_tally
    @chuu_ren_bou_tou_tally ||= begin
      numbers.clone.tap do |n|
        # note: cannot use arr1 - arr2 as it deletes all duplicates
        [1,1,1,2,3,4,5,6,7,8,9,9,9].all? do |i|
         return false unless matched_index = n.index(i)
          n.delete_at(matched_index)
        end
      end
    end
  end






  def ankou_yaku?(formation)
    case get_ankou_count(formation)
    when 4
      @yakuman_yaku << '四暗刻'
    when 3
      @yaku << '三暗刻'
    end
  end

  def get_ankou_count(formation)
    # if machi_hai is zyantou, then 4 no matter tumou or not; if machi_hai is kotu/not zyantou, then 4 only if tumo
    kotu_in_mentu = formation[:mentu].select { |group| %w(刻 暗槓).include?(group[:type]) }
    if !tumo
      machi_hai = Pai.convert_character(machi)
      zyantou = formation[:zyantou]
      kotu_in_mentu.reject! { |kotu| kotu[:suit] == machi_hai[:suit] && kotu[:number] == machi_hai[:number] }
    end
    kotu_count_in_furou = furou.count { |group| group[:type] == '刻' }
    kotu_in_mentu.count - kotu_count_in_furou
  end

  def chantaiyaokyuu_yaku?(formation)
    return if @routou_yaku
    zihai_groups, number_groups = (formation[:mentu] + [formation[:zyantou]]).partition { |group| group[:suit] == '字' }
    same_groups, jun_groups = number_groups.partition { |group| %w(対 刻 暗槓 大明槓).include?(group[:type]) }
    return unless same_groups.all? { |group| [1, 9].include?(group[:number]) }
    return unless jun_groups.all? { |group| [1, 7].include?(group[:number]) }

    if zihai_groups.any?
      @yaku << '混全帯么九'
    else
      @yaku << '純全帯么九'
    end
  end

  def get_menzenchin_yaku(formation)
    return unless is_menzenchin?
    peikou_yaku?(formation)
    pinfu?(formation)
  end

  def peikou_yaku?(formation)
    jun_groups = formation[:mentu].select { |group| group[:type] == '順' }

    case jun_groups.uniq.count
    when 2
      @yaku << '二盃口'
    when 3
      @yaku << '一盃口'
    end
  end

  def pinfu?(formation)
    return if yaku_hai?(formation[:zyantou])
    return unless formation[:mentu].all? { |group| group[:type] == '順' }
    machi_hai = Pai.convert_character(machi)
    suit, number = machi_hai[:suit], machi_hai[:number]
    posssible_start_numbers = [number - 2, number, number + 2].select { |i| i >= 1 && i <= 9 }
    return unless formation[:mentu].any? { |group| group[:suit] == suit && posssible_start_numbers.include?(group[:number]) }
    @yaku << '平和'
  end

  def yaku_hai?(group)
    return false unless group[:suit] == '字'
    [5,6,7, chanfon, zifon].include?(group[:number])
  end

  # rest:  sankantu suukantu toitoi ikkituukan sanshoku

  def calculate
    # to be implemented
  end
end

class FormationYakuIdentifier
  def initialize(mentu:, zyantou:, machi_hai:, furou: [], tumo: false, routou: false)
    @mentu = mentu
    @zyantou = zyantou
    @machi_hai = machi_hai
    @furou = furou
    @routou = routou
  end
end

# "字" => %w(東 南 西 北 白 發 中),
# "萬" => %w(一 二 三 四 五 六 七 八 九),
# "筒" => %w(① ② ③ ④ ⑤ ⑥ ⑦ ⑧ ⑨),
# "索" => %w(1 2 3 4 5 6 7 8 9)

# y = YakuIdentifier.new(menzen: "東東東南南南西西西北北99", machi:"9", chanfon: 2)
# y = YakuIdentifier.new(menzen: "白白白發發發中中中北北99", machi:"9", chanfon: 2)
# y = YakuIdentifier.new(menzen: "2223334446668", machi:"8")
# y = YakuIdentifier.new(menzen: "1113345678999", machi:"2")
y = YakuIdentifier.new(menzen: "2333444666888", machi:"2")
y.run

binding.pry

# samples = CacheGenerator.get_combinations(max_tiles: 14).sample(10)
# samples.each {|s| p s; puts "\n"; pp GeneralGrouper.group(menzen: s.join(""), furou: [], return_one: false); puts "\n\n\n" }
