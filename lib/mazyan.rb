require 'pry'
require 'json'
require 'benchmark'

class Hai
  # attr_reader :suit, :number, :character    ### currently using a hash to represent the attributes instead of creating a Hai/Hai object

  class InvalidCharacterError < StandardError
  end

  TILES = {
    "字" => %w(東 南 西 北 白 發 中),
    "萬" => %w(一 二 三 四 五 六 七 八 九),
    "筒" => %w(① ② ③ ④ ⑤ ⑥ ⑦ ⑧ ⑨),
    "索" => %w(1 2 3 4 5 6 7 8 9)
  }

  GREEN = %w(2 3 4 6 8 發)

  attr_reader :suit, :number, :character

  def initialize(suit:, number:, character:)
    @suit = suit
    @number = number
    @character = character
  end

  def zi?
    suit == "字"
  end

  def number?
    !zi?
  end

  def yao_kyuu?
    number? && [1, 9].include?(number)
  end

  # not sure if useful
  def green?
    GREEN.include?(character)
  end

  def characters
    character
  end

  class << self
    def convert_characters(characters)
      characters = characters.scan(/[^\s|,]/)
      characters.map { |c| convert_character(c) }
    end

    def convert_character(character)
      get(character)
    end

    def get(*param)
      lookup[param]
    end

    def lookup
      @lookup ||= generate_all[0]
    end

    def all
      @all ||= generate_all[1]
    end

    def generate_all
      @lookup = {}
      @all = {}

      TILES.each do |suit, characters|
        characters.each_with_index do |character, i|
          hai = Hai.new(suit: suit, number: i + 1, character: character)
          @lookup[[character]] = hai
          @all[suit] ||= []
          @all[suit] << hai
        end
      end

      [@lookup, @all]
    end
  end
end

class NumGrouper
  FORMATIONS = [
    { symbol: "刻", category: "mentu",  method: :same },
    { symbol: "順", category: "mentu",  method: :sequence },
    { symbol: "対", category: "kouhou", method: :same },
    { symbol: "塔", category: "kouhou", method: :sequence },
    { symbol: "嵌", category: "kouhou", method: :kanchan },
  ]
  CACHE_FILE_PATH = 'simple_cache.json'

  # BUG: cannot use same cache for ZihaiGrouper, as it will return valid zihai jun groups
  def self.load_cache
    if File.exist?(CACHE_FILE_PATH)
      c = JSON.parse(File.read(CACHE_FILE_PATH))
      @cache = c.map { |key, tallies|
        symbolized_tallies = tallies.map { |tally|
          tally.map { |group| group.class == Array ? [ group[0].to_sym, group[1]] : group }
        }
        [key, symbolized_tallies]
      }.to_h
    else
      @cache = nil
    end
  end

  def self.cache
    @cache
  end
  # NumGrouper.load_cache

  attr_reader :suit, :return_one

  def initialize(all_numbers, return_one: false)
    @all_numbers = all_numbers
    @return_one = return_one
  end

  def run
    results = group(@all_numbers, [])
    remove_same(results)
  end

  def group(numbers, tally) # sorted
    if self.class.cache
      cached_tally =  self.class.cache[numbers.join("")]
      if cached_tally
        combined_tallies = combine_tallies(cached_tally, tally)
        return [combined_tallies.first] if return_one
        return combined_tallies
      end
    end

    num_of_tiles = numbers.size
    return wrap(tally) if num_of_tiles.zero?

    first = numbers[0]
    return wrap(tally_isolated(tally, first)) if num_of_tiles == 1
    return group_without_first(first, numbers, tally) if first_is_isolated?(first, numbers)

    tallies = self.class.const_get("FORMATIONS").each_with_object([]) do |formation, arr|
      grouped = group_formation(formation, first, numbers, num_of_tiles, tally)
      arr << grouped if grouped
    end

    tallies << group_without_first(first, numbers, tally)

    tallies = tallies.flatten(1)
    tallies, _ = best_tally(tallies)
    tallies
  end

  def wrap(tally)
    [tally]
  end

  def combine_tallies(tally1, tally2)
    arr = []
    tally1.each do |t1|
      arr << t1.clone + tally2
    end
    arr
  end

  def remove_same(tallies)
    return tallies if tallies.count == 1
    set = tallies.inject({}) do |h, tally|
      h[tally.map(&:to_s).sort.join] = tally
      h
    end
    set.values
  end

  def group_without_first(first, numbers, tally)
    group(numbers[1..-1], tally_isolated(tally, first))
  end

  def group_formation(formation, first, numbers, num_of_tiles, tally)
    symbol       = formation[:symbol]
    category     = formation[:category]
    num_to_group = get_num_to_group(category)
    method       = formation[:method]

    grouped, remaining = send("group_#{method}", first, numbers, num_of_tiles, num_to_group)
    group(remaining, tally_with_category(tally, symbol, first)) if grouped
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
    _tally = tally.clone
    _tally += [[:"孤", number]]
  end

  def tally_with_category(tally, symbol, number)
    _tally = tally.clone
    _tally += [[:"#{symbol}", number]]
  end

  def get_remaining(numbers, to_remove)
    numbers = numbers.clone
    to_remove.each { |i| numbers.delete_at(numbers.index(i)) }
    numbers
  end

  def best_tally(tallies)
    hai_count = get_hai_count(tallies.first)
    max_mentu = hai_count / 3
    scores_with_mentu = tallies.map { |t| get_score(t, hai_count, max_mentu) }
    scores, mentu = scores_with_mentu.map(&:first), scores_with_mentu.map(&:last)
    best_score = scores.min
    # allow both tallies with shantei 0 and -1 to be returned as combining with other suits could result in either being 0
    # but return only agari tally when the hai count is 14
    best_score = 0 if best_score < 0 && hai_count != 14
    indices_with_best_score = (0...scores.size).select { |i| scores[i] <= best_score }
    tallies = indices_with_best_score.map { |i| tallies[i] }

    # place tallies with lowest shantei count in front;
    # as well as highest mentu count
    # so that return_one/the first one would return that
    if best_score == 0
      tallies = tallies.each_with_index.sort_by { |tally, i| scores[i] - mentu[i] * 0.1 }.map(&:first)
    end

    return [[tallies.first], best_score] if return_one
    [tallies, best_score]
  end

  # benchmarking shows this is the most intensive operation, instead of number splitting
  # i.e. calling more of this method would slow down performance
  # using symbols improve the perf. by 33%
  # althogh none of this matters if the result is cached
  def get_score(tally, hai_count=nil, max_mentu=nil)
    mentu, kouhou, isolated, zyantou = count_category(tally)
    hai_count ||=  3 * mentu + 2 * kouhou + isolated
    max_mentu ||= hai_count / 3

    shantei = (max_mentu - mentu) * 2 - [max_mentu - mentu, kouhou - zyantou].min - zyantou
    return [shantei, mentu] if shantei != 0

    # normally, when there are 13 hais (4 mentu + 1 or 3 mentu + 2 kouhou), the shantei formula is not affected by the isolated count
    # but if hai_count %3 == 2, e.g. 5, shantei of [1,234,5] and [12,345] will be the same which is weird
    # thus it is adjusted
    # note, cannot simply add isolated * 0.01 or mentu * 0.01 to formula, as this would be biased in cases like [111,2,333] vs. [11,123,33]
    if hai_count % 3 == 2 && isolated != 0
      [1, mentu]
    else
      [0, mentu]
    end
  end

  def get_hai_count(tally)
    mentu, kouhou, isolated, zyantou = count_category(tally)
    hai_count = 3 * mentu + 2 * kouhou + isolated
  end

  def count_category(tally)
    partition_by_category(tally).map(&:count)
  end

  def partition_by_category(tally)
    mentu, incomplete_mentu, isolated, zyantou = [], [], [], []
    tally.each do |elem|
      case type = elem[0]
      when :"刻", :"順"
        mentu << elem
      when :"対", :"塔", :"嵌"
        incomplete_mentu << elem
        zyantou = [elem] if type == :"対"
      else
        isolated << elem
      end
    end
    [mentu, incomplete_mentu, isolated, zyantou]
  end
end

class ZihaiGrouper < NumGrouper
  FORMATIONS = [
    { symbol: "刻", category: "mentu",  method: :same },
    { symbol: "対", category: "kouhou", method: :same },
  ]

  def self.load_cache
    nil
  end
  
  def self.cache
    nil
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

    def get_all_combinations(max_repeat: 4, min_tiles: 1, max_tiles: 14, start_from: 1, up_to: 9)
      (min_tiles..max_tiles).each_with_object([]) do |i, arr|
        arr << get_combinations(max_repeat: max_repeat, max_tiles: i, start_from: start_from, up_to: up_to)
      end.flatten(1)
    end

    # benchmarking shows,
    # no cache rakes 0.04 s. per run
    # even with a very simple cache with max 3-combination, is able to speed up performance by 50%
    # using a 10-number cache, it is able to reach 0.0004 s. per run
    # vs. the full 14-number cache, that takes 0.00015 s. per run
    # but the full cache takes up a lot of memory as well as time to load into memory
    # thus it may be more beneficial to use the simpler 10-number cache
    # expecially considering most of the time, the Grouper is not going to have to group 10+ number of the same suit
    def generate_cache(file = NumGrouper::CACHE_FILE_PATH, max_tiles = 3)
      hash = {}
      combinations = get_all_combinations(max_tiles: max_tiles)
      combinations.each do |numbers|
        value = NumGrouper.new(numbers).run
        key = numbers.join("")
        hash[key] = value
      end
      File.open(file, 'w+') { |f| f.write(hash.to_json) }
      return if max_tiles == 10# 14
      NumGrouper.load_cache
      generate_cache(file, max_tiles + 1)
    end

    # Can generate a second cache base on the full cache, that returns only one tally(first) unless shantei is 0/-1
    # this would help save on cache size
  end
end

# benchmarking shows there is negligible difference by caching the base of the mentu (i.e. the number group & methods)
# compared to creating a new object during the calculation
class Mentu
  attr_reader :menzen, :suit, :number, :type, :symbol

  def initialize(menzen:, suit:, number:, type:, symbol:)
    @menzen = menzen
    @suit = suit
    @number = number # smallest number in the group
    @type = type
    @symbol = symbol
  end

  def mentu?
    @mentu ||= %i(槓 刻 順).include?(type)
  end

  def incomplete_mentu?
    @incomplete_mentu ||= %i(対 嵌 塔).include?(type)
  end

  def isolated?
    @isolated ||= type == :"孤"
  end

  def zyantou?
    @zyantou ||= type == :"対"
  end

  def kotu?
    @kotu ||= :"刻" == type
  end

  def kan?
    @kan ||= :"槓" == type
  end

  def jun?
    @jun ||= :"順" == type
  end

  def tai_yao_kyuu?
    @tai_yao_kyu ||= if jun?
      (number == 1 || number == 7)
    else
      yao_kyuu?
    end
  end

  def yao_kyuu?
    @yao_kyuu ||= !jun? &&
      (number == 1 || number == 9)
  end

  def an_kou?
    (kotu? || kan?) && menzen?
  end

  def an_kan?
    kan? && menzen?
  end

  def mei_kan?
    kan? && !menzen?
  end

  def menzen?
    @menzen
  end

  def characters
    @characters ||= self.class.symbol_to_characters[symbol]
  end

  def hais
    @hais ||= characters.map { Hai.get(character) }
  end

  def self.from_symbol(menzen:, symbol:)
    suit, type, number = symbol.split("")
    new(menzen: menzen, suit: suit.to_sym, type: type.to_sym, number: number, symbol: symbol.to_sym)
  end

  def self.from_characters(menzen:, characters:)
    symbol = self.class.characters_to_symbol[characters]
    from_symbol(menzen: menzen, symbol: symbol)
  end

  def self.characters_to_symbol
    @characters_to_symbol ||= begin
      h = {}
      symbol_to_characters.each do |k, v|
        h[v] = k
      end
      h
    end
  end

  def self.symbol_to_characters
    @symbol_to_characters ||= begin
      h = {}
      Hai::TILES.each do |suit, characters|
        characters.each_with_index do |character, i|
          number = i + 1
          h["#{suit}槓#{number}"] = character * 4
          h["#{suit}刻#{number}"] = character * 3
          h["#{suit}対#{number}"] = character * 2
          h["#{suit}孤#{number}"] = character
          next if suit == '字'
          next if i > 7
          h["#{suit}順#{number}"] = characters[i..i+2].join
          h["#{suit}嵌#{number}"] = [characters[i], characters[i+2]].join
          next if i > 8
          h["#{suit}塔#{number}"] = characters[i..i+1].join
        end
      end
      h
    end
  end
end

class MenzenGrouper
  # should be instance method
  attr_reader :hais, :return_one

  def initialize(hais:, return_one: true)
    @hais = hais
    @return_one = return_one
  end

  def run
    tallies_per_suit = separated_hais.map do |suit, numbers|
      grouper = suit == "字" ? ZihaiGrouper : NumGrouper
      tallies = grouper.new(numbers, return_one: return_one).run
      tallies.map { |tally| tally.map{ |symbol| into_mentu(suit, symbol) } }
    end
    possibilities = get_permutations(tallies_per_suit)
    possibilities.map { |p| p.flatten }
  end

  def separated_hais
    @separated_hais ||= begin
      hash = hais.group_by(&:suit)
      hash.map { |suit, hais| [suit, hais.map(&:number).sort] }.to_h
    end
  end

  def into_mentu(suit, symbol)
    Mentu.from_symbol(menzen: true, symbol: "#{suit}#{symbol.join}")
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
    return group if group.class == Mentu
    characters = group.scan(/[^\s|,]/).join
    Mentu.from_characters(menzen: false, characters: characters)
  end

  def into_number(input)
    return input if input.class == Integer
    Hai.convert_character(input)[:number]
  end

  def as_hais(menzen)
    menzen.map { |m| as_hai(m) }
  end

  def as_hai(input)
    return input if input.class == Hai
    Hai.convert_character(input)
  end
end

class GeneralGrouper
  attr_reader :menzen, :furou, :return_one, :shantei, :formations

  def initialize(menzen: , furou: [], return_one: true)
    @menzen = menzen # array [Hai]
    @furou = furou # array [Mentu]
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

    tallies = MenzenGrouper.new(hais: menzen, return_one: return_one).run
    tallies.map! do |tally|
      tally += furou
    end
    @tallies = tallies
  end

  def get_shantei_from_tally(tally)
    mentu, incomplete_mentu, isolated, zyantou = %w(mentu? incomplete_mentu? isolated? zyantou?).map { |type| tally.count { |m| m.send(type) } }
    zyantou = 1 if zyantou >= 1

    8 - 2 * mentu - [4 - mentu, incomplete_mentu - zyantou].min - zyantou
  end
end

# include RegularizeHelper
# NumGrouper.load_cache


# all_hai = Hai.all.values.flatten
# Benchmark.bm do |x|
#   x.report do
#     10000.times do
#       hais = (0...14).map { all_hai.sample }
#       g = GeneralGrouper.new(menzen: hais).run
#     end
#   end
# end

class KokuShiMuSouGrouper
  KOKUSHI_CHARACTERS = %w(東 南 西 北 白 發 中 一 九 ① ⑨ 1 9)

  attr_reader :shantei, :machi, :zyantou_char, :unmatched_characters, :matched_kokushi_characters

  def initialize(menzen:)
    @menzen = menzen # accept hais only

    @unmatched_characters = menzen.map(&:character)
    @matched_kokushi_characters = []
    @shantei = nil
    @machi = nil
    @zyantou_char = nil
  end

  def run
    # first pass
    KOKUSHI_CHARACTERS.each do |kokushi_char|
      match_kokushi_char(kokushi_char)
    end

    # second pass
    @zyantou_char = KOKUSHI_CHARACTERS.find do |kokushi_char|
      match_kokushi_char(kokushi_char)
    end

    @machi = KOKUSHI_CHARACTERS - matched_kokushi_characters
    unless zyantou_char
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

    @characters = menzen.map(&:character)
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


class ShanteiCalculator
  include RegularizeHelper

  attr_reader :menzen, :furou, :general_grouper,
    :kokushi_grouper, :chitoitu_grouper, :groupers, :shantei, :quick_find, :shantei

  class WrongNumberOfHaisError < StandardError; end

  def initialize(menzen:, furou: [], quick_find: true)
    @menzen = as_hais(as_array(menzen)) # consider only accept hais
    @furou = as_formations(furou)
    @quick_find = quick_find
  end

  def run
    validate_hai_count

    @general_grouper = GeneralGrouper.new(menzen: menzen, furou: furou, return_one: quick_find)
    if furou.empty?
      @kokushi_grouper = KokuShiMuSouGrouper.new(menzen: menzen)
      @chitoitu_grouper = ChiToiTuGrouper.new(menzen: menzen)
    end
    @groupers = [@general_grouper, @kokushi_grouper, @chitoitu_grouper].compact
    groupers.each { |grouper| grouper.run }

    @shantei = groupers.map{ |g| g.shantei }.min
  end

  def validate_hai_count
    raise WrongNumberOfHaisError unless menzen.size / 3 + furou.size == 4 && menzen.size % 3 != 0
  end
end

require 'forwardable'
class YakuIdentifier
  extend Forwardable
  include RegularizeHelper

  class KokushiMuSouFormation
  end

  class ChiToiTuFormation
    def get_fu
      {
        subtotals: { "七対子" => 25 },
        total: 25
      }
    end
  end

  attr_reader :menzen, :furou, :agari, :tumo, :richi, :double_richi, :ipatu,
    :rinshan, :chankan, :haitei, :first_jun, :dora_count, :chanfon, :zifon,
    :shared_yaku, :yaku_map, :formations,
    :hais, :zi_hais, :number_hais, :numbers, :all_suits,
    :yakuman_multiple, :han, :fu, :han_details, :fu_details

  delegate [:shantei, :general_grouper, :kokushi_grouper, :chitoitu_grouper] => :shantei_calc
  delegate [:formations] => :general_grouper

  class WrongNumberOfHaisError < StandardError; end
  class InvalidSituation < StandardError; end
  class NotAgariError < StandardError; end

  ZIHAI = %w(東 南 西 北 白 發 中)
  ROUIUSOU_HAIS = %w(2 3 4 6 8 發)

  class_eval do
    ZIHAI.each do |zihai|
      define_method :"has_three_#{zihai}" do
        zi_hais_tally["#{zihai}"] >= 3
      end

      define_method :"has_two_#{zihai}" do
        zi_hais_tally["#{zihai}"] >= 2
      end
    end
  end

  # menzen arg must include the agari in it as well
  def initialize(
    menzen:,
    agari:,
    furou: [],
    tumo: false,
    richi: false,
    double_richi: false,
    ipatu: false,
    rinshan: false,
    chankan: false,
    haitei: false,
    first_jun: false,
    dora_count: 0,
    oya: false,
    chanfon: 1,
    zifon: 1
    )
    @menzen         = as_hais(as_array(menzen))
    @furou          = as_formations(furou)
    @agari          = as_hai(agari)

    @richi          = double_richi || richi
    @double_richi   = double_richi
    @ipatu          = ipatu
    @tumo           = tumo

    # I feel the following 5 can be part of an options hash
    @rinshan        = rinshan
    @chankan        = chankan
    @haitei         = haitei
    @first_jun      = first_jun
    @dora_count     = dora_count

    @chanfon        = into_number(chanfon)
    @zifon          = into_number(zifon)
    @shared_yaku    = [] # yaku that does not depend on formation
    @yaku_map       = {}
  end

  def run
    prepare_helpers

    validate

    get_yaku
  end

  def oya
    @oya ||= zifon == 1
  end

  def prepare_helpers
    @hais = (@menzen + @furou.map { |f| f[:hais] }).flatten + [@agari]
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
    raise InvalidSituation if first_jun && (!tumo || !is_menzenchin?)

    shantei_calc.run
    raise NotAgariError unless shantei == -1
  end

  def shantei_calc
    @shantei_calc ||= ShanteiCalculator.new(
      menzen: menzen + [agari],
      furou: furou,
      quick_find: false
    )
  end

  YAKU_RULES = [
    { name: "天和", requirements: [:first_jun, :oya] },
    { name: "地和", requirements: [:first_jun], mutually_exclusive: ["天和"] },
    { name: "純正国士無双", requirements: [:is_menzenchin?, :is_jun_sei_kokushi] },
    { name: "国士無双", requirements: [:is_menzenchin?, :is_kokushi], mutually_exclusive: ["純正国士無双"] },
    { name: "七対子", requirements: [:is_menzenchin?, :is_chitoitu] }, # or exclusive with ryanpeikou
    { name: "W立直", requirements: [:is_menzenchin?, :double_richi] },
    { name: "立直", requirements: [:is_menzenchin?, :richi], mutually_exclusive: ["W立直"] },
    { name: "一発", requirements: [:is_menzenchin?, :richi, :ipatu] },
    { name: "嶺上開花", requirements: [:rinshan] },
    { name: "搶槓", requirements: [:chankan] },
    { name: "門前清自摸和", requirements: [:is_menzenchin?, :tumo] },
    { name: "海底摸月", requirements: [:haitei, :tumo] },
    { name: "河底撈魚", requirements: [:haitei], mutually_exclusive: ["海底摸月"] },
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

  YAKU_MAN_MULTIPLE = {
    "純正国士無双" => 2,
    "純正九蓮宝燈" => 2,
    "四暗刻単騎" => 2,
    "大四喜" => 2,
    "国士無双" => 1,
    "四暗刻" => 1,
    "四槓子" => 1,
    "九蓮宝燈" => 1,
    "緑一色" => 1,
    "清老頭" => 1,
    "字一色" => 1,
    "小四喜" => 1,
    "大三元" => 1,
    "天和" => 1,
    "地和" => 1
  }

  YAKU_HAN = {
    "七対子" => [2, 2],
    "W立直" => [2, nil],
    "立直" => [1, nil],
    "一発" => [1, nil],
    "嶺上開花" => [1, 1],
    "搶槓" => [1, 1],
    "門前清自摸和" => [1, nil],
    "海底摸月" => [1, 1],
    "河底撈魚" => [1, 1],
    "断么九" => [1, 1],
    "混老頭" => [2, 2],
    "清一色" => [6, 5],
    "混一色" => [3, 2],
    "小三元" => [2, 2],
    "役牌 白" => [1, 1],
    "役牌 發" => [1, 1],
    "役牌 中" => [1, 1],
    "場風" => [1, 1],
    "自風" => [1, 1],
    "三暗刻" => [2, 2],
    "対々和" => [2, 2],
    "三槓子" => [2, 2],
    "純全帯么九" => [3, 2],
    "混全帯么九" => [2, 1],
    "二盃口" => [3, nil],
    "一盃口" => [1, nil],
    "平和" => [1, nil],
    "一気通貫" => [2, 1],
    "三色同順" => [2, 1],
    "三色同刻" => [2, 2]
  }

  def get_yaku
    YAKU_RULES.each do |rule|
      next if rule[:mutually_exclusive] && (shared_yaku & rule[:mutually_exclusive]).any?
      next unless rule[:requirements].all? { |req| send(req) }
      @shared_yaku << rule[:name]
    end

    if (shared_yaku & %w(純正国士無双 国士無双)).any?
      yaku_map[KokushiMuSouFormation.new] = shared_yaku
    elsif (shared_yaku & %w(七対子)).any?
        yaku_map[ChiToiTuFormation.new] = shared_yaku
    else
      formations.map do |f|
        f_identifier = FormationYakuIdentifier.new(formation: f, model: self)
        yaku_map[f_identifier] = f_identifier.get_yaku
      end
    end

    calculate
  end

  def is_menzenchin?
    @is_menzenchin ||= @furou.all? { |f| f[:type] == "暗槓" } # this includes @furou.empty?
  end

  def is_jun_sei_kokushi
    is_kokushi &&
      kokushi_grouper.zyantou_char == agari[:character]
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
      chuu_ren_bou_tou_tally.first == agari[:number]
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

  def calculate
    totals = yaku_map.map do |formation, yaku_list|
      h = YAKU_MAN_MULTIPLE.slice(*yaku_list)
      if h.any?
        multiple = h.values.sum
        { yaku_man_multiple: multiple, han: multiple * 13, details: h, formation: formation }
      else
        h = YAKU_HAN.slice(*yaku_list)
        h = h.map { |k, arr| is_menzenchin? ? [k, arr[0]] : [k, arr[1]] }.to_h
        { han: h.values.sum, details: h, formation: formation }
      end
    end

    best = totals.max_by { |h| h[:han] }
    @yakuman_multiple = best[:yaku_man_multiple]
    @han = best[:han]
    @han_details = best[:details]

    if dora_count > 0
      @han += dora_count
      @han_details["ドラ"] = dora_count
    end

    if @han < 5
      fu_h = best[:formation].get_fu
      @fu_details, @fu = fu_h[:subtotals], fu_h[:total]
    end

    pp yakuman_multiple, han, han_details, fu, fu_details
  end
end

class FormationYakuIdentifier
  extend Forwardable

  attr_reader :model, :formation, :yaku

  delegate [:menzen, :furou, :agari, :is_menzenchin?, :tumo, :no_zi_hais, :chanfon, :zifon] => :model

  def initialize(formation:, model:)
    @formation = formation
    @model = model
    @yaku = model.shared_yaku.dup
  end

  def mentu
    formation["mentu"]
  end

  # formation['zyantou'] is a boolean referring to if zyantou exists; this returns the actual group
  def zyantou
    formation["kouhou"].first
  end

  def menzen_mentu
    formation["menzen_mentu"]
  end

  def kotu_mentu
    @kotu_mentu ||= split_mentu_by_type[0]
  end

  def jun_mentu
    @jun_mentu ||= split_mentu_by_type[1]
  end

  def kan_mentu
    @kan_kentu ||= an_kan_mentu + mei_kan_mentu
  end

  def an_kan_mentu
    @an_kan_mentu ||= split_mentu_by_type[2]
  end

  def mei_kan_mentu
    @mei_kan_mentu ||= split_mentu_by_type[3]
  end

  def split_mentu_by_type
    @kotu_mentu, @jun_mentu, @an_kan_mentu, @mei_kan_mentu = [], [], [], []
    mentu.each do |group|
      case group[:type]
      when "刻"
        @kotu_mentu << group
      when "順"
        @jun_mentu << group
      when "暗槓"
        @an_kan_mentu << group
      when "加槓", "大明槓"
        @mei_kan_mentu << group
      else
        raise 'unrecognized type'
      end
    end
    [@kotu_mentu, @jun_mentu, @an_kan_mentu, @mei_kan_mentu]
  end

  def number_mentu
    @number_mentu ||= split_mentu_by_suit.last
  end

  def split_mentu_by_suit
    @zi_hai_mentu, @number_mentu = mentu.partition { |group| group[:suit] == '字' }
  end

  FORMATION_YAKU_RULES = [
    { name: "四暗刻単騎", requirements: [:is_menzenchin?, :shi_an_kou_tan_ki?] },
    { name: "四暗刻", requirements: [:is_menzenchin?, :suu_an_kou?], mutually_exclusive: ["四暗刻単騎"] },
    { name: "三暗刻", requirements: [:san_an_kou?], mutually_exclusive: ["四暗刻"] },
    { name: "対々和", requirements: [:toitoi?] },
    { name: "四槓子", requirements: [:suu_kan_tu?] },
    { name: "三槓子", requirements: [:san_kan_tu?], mutually_exclusive: ["四槓子"] },
    { name: "純全帯么九", requirements: [:tai_yao_kyu?, :no_zi_hais], mutually_exclusive: ["清老頭", "混老頭"] },
    { name: "混全帯么九", requirements: [:tai_yao_kyu?], mutually_exclusive: ["純全帯么九", "清老頭", "混老頭"] },
    { name: "二盃口", requirements: [:is_menzenchin?, :ryan_pei_kou?] },
    { name: "一盃口", requirements: [:is_menzenchin?, :ii_pei_kou?], mutually_exclusive: ["二盃口"] },
    { name: "平和", requirements: [:pinfu?] },
    { name: "一気通貫", requirements: [:ik_ki_tuu_kan?] },
    { name: "三色同順", requirements: [:san_shoku_dou_jun] },
    { name: "三色同刻", requirements: [:san_shoku_dou_kou] }
  ]

  def get_yaku
    FORMATION_YAKU_RULES.each do |rule|
      next if rule[:mutually_exclusive] && (yaku & rule[:mutually_exclusive]).any?
      next unless rule[:requirements].all? { |req| send(req) }
      @yaku << rule[:name]
    end
    yaku
  end

  def shi_an_kou_tan_ki?
    suu_an_kou? &&
      menzen_kotu.none? { |kotu| kotu_match_agari?(kotu) }
  end

  def suu_an_kou?
    menzen_kotu.count == 4
  end

  def san_an_kou?
    menzen_kotu.count == 3
  end

  def menzen_kotu
    return @menzen_kotu if @menzen_kotu

    @menzen_kotu = menzen_mentu.select { |group| group[:type] == "刻" } + an_kan_mentu
    return @menzen_kotu if tumo

    @menzen_kotu.reject { |kotu| kotu_match_agari?(kotu) }
  end

  def kotu_match_agari?(kotu)
    kotu[:suit] == agari[:suit] &&
      kotu[:number] == agari[:number]
  end

  def toitoi?
    (kotu_mentu + kan_mentu).size == 4
  end

  def suu_kan_tu?
    kan_mentu.count == 4
  end

  def san_kan_tu?
    kan_mentu.count == 3
  end

  def tai_yao_kyu?
    (number_mentu + [zyantou]).all? { |group| tai_yao_kyu_group?(group) }
  end

  # consider making group as a Class, and this could be an instance method
  def tai_yao_kyu_group?(group)
    return false if group[:type] == '字'
    case group[:type]
    when "対", "刻", "暗槓", "加槓", "大明槓"
      [1, 9].include?(group[:number])
    else
      [1, 7].include?(group[:number])
    end
  end

  def ryan_pei_kou?
    pei_kou_count == 2
  end

  def ii_pei_kou?
    pei_kou_count == 1
  end

  def pei_kou_count
    @pei_kou_count ||= begin
      h = Hash.new(0)
      jun_mentu.each { |group| h[group] += 1 }
      h.values.map { |v| v / 2 }.sum
    end
  end

  def pinfu?
    is_menzenchin? && pinfu_gata?
  end

  def pinfu_gata?
    @pinfu_gata ||= begin
      return if yaku_hai?(zyantou)
      return unless jun_mentu.count == 4
      ryo_men_machi?
    end
  end

  def yaku_hai?(group)
    get_yaku_hai(group).any?
  end

  def get_yaku_hai(group)
    return [] unless group[:suit] == '字'
    [5,6,7, chanfon, zifon].select { |i| i == group[:number] }
  end

  def ryo_men_machi?
    possible_mentu_for_agari.values.include?('両面待ち')
  end

  # to do: refactor
  # note: reuse for fu-calculation
  def possible_mentu_for_agari
    @possible_mentu_for_agari ||= begin
      h = {}

      (menzen_mentu + [zyantou]).select do |group|
        next unless group[:suit] == agari[:suit]

        case group[:type]
        when '順'
          case agari[:number] - group[:number]
          when 0
            h[group] = group[:number] == 7 ? '辺張待ち' : '両面待ち'
          when 1
            h[group] = '嵌張待ち'
          when 2
            h[group] = group[:number] == 1 ? '辺張待ち' : '両面待ち'
          else
            next
          end
        when '刻'
          next unless group[:number] == agari[:number]
          h[group] = 'シャボ一待ち'
        when '対'
          next unless group[:number] == agari[:number]
          h[group] = '単騎待ち'
        end
      end

      h
    end
  end

  def ik_ki_tuu_kan?
    return false unless jun_mentu.size >= 3
    h = jun_mentu.group_by { |group| group[:suit] }
    h.values.any? do |arr|
      arr.size >=3 &&
        (arr.map { |group| group[:number] } & [1,4,7]).size == 3
    end
  end

  def san_shoku_dou_jun
    san_shoku?(jun_mentu)
  end

  def san_shoku_dou_kou
    san_shoku?(kotu_mentu)
  end

  def san_shoku?(mentu)
    return false unless mentu.size >= 3
    h = mentu.group_by { |group| group[:number] }
    h.values.any? do |arr|
      all_three_suits?(arr)
    end
  end

  def all_three_suits?(arr)
    arr.size >= 3 &&
      (arr.map { |group| group[:suit] } & ["萬", "筒", "索"]).size == 3
  end

  def get_fu
    @fu ||= FuCalculator.new(identifier: self).run
  end
end

class FuCalculator
  extend Forwardable

  attr_reader :identifier, :subtotals

  delegate [
    :formation,
    :is_menzenchin?,
    :tumo,
    :menzen_kotu,
    :furou,
    :zyantou,
    :chanfon,
    :zifon,
    :possible_mentu_for_agari,
    :yaku_hai?,
    :get_yaku_hai,
    :tai_yao_kyu_group?,
    :pinfu?
  ] => :identifier

  def initialize(identifier:)
    @identifier = identifier
    @subtotals = {}
  end

  def run
    if pinfu? && tumo
      pinfu_tumo_fu
    else
      men_zen_ron_fu
      tumo_fu
      mentu_fu
      zyantou_fu
      machi_fu
      base_fu
    end

    get_total
  end

  def pinfu_tumo_fu
    @subtotals["平和ツモ"] = 20
  end

  def men_zen_ron_fu
    return unless is_menzenchin? && !tumo
    @subtotals["面前ロン"] = 10
  end

  def tumo_fu
    return unless tumo
    @subtotals["ツモ"] = 2
  end

  # note: should have some way to separate ankou and meikou
  def mentu_fu
    point = menzen_kotu.sum { |kotu| apply_multipliers(kotu, 4) } +
      (furou - menzen_kotu).sum { |group| apply_multipliers(group, 2) }
    return unless point > 0
    @subtotals["面子"] = point
  end

  def apply_multipliers(group, point)
    point *= 0 if group[:type] == "順"
    point *= 4 if group[:type][-1] == "槓"
    point *= 2 if yaku_hai?(group)
    point *= 2 if tai_yao_kyu_group?(group)
    point
  end

  def zyantou_fu
    point = get_yaku_hai(zyantou).count
    return unless point > 0
    @subtotals["アタマ"] = point * 2
  end

  def machi_fu
    single_machi = (possible_mentu_for_agari.values & ['辺張待ち', '嵌張待ち', '単騎待ち']).first
    return unless single_machi
    @subtotals[single_machi] = 2
  end

  def base_fu
    if @subtotals.any?
      @subtotals["副底"] = 20
    else
      @subtotals["喰い平和型"] = 30
    end
  end

  def get_total
    {
      subtotals: subtotals,
      total: (subtotals.values.sum / 10.to_f).ceil * 10
    }
  end
end

# "字" => %w(東 南 西 北 白 發 中),
# "萬" => %w(一 二 三 四 五 六 七 八 九),
# "筒" => %w(① ② ③ ④ ⑤ ⑥ ⑦ ⑧ ⑨),
# "索" => %w(1 2 3 4 5 6 7 8 9)

# y = YakuIdentifier.new(menzen: "東東東南南南西西西北北北中", agari:"中", chanfon: 2)
# y = YakuIdentifier.new(menzen: "白白白發發發中中中北北99", agari:"9", chanfon: 2)
# y = YakuIdentifier.new(menzen: "2223334446668", agari:"8")
# y = YakuIdentifier.new(menzen: "1113345678999", agari:"2")
# y = YakuIdentifier.new(menzen: "2233344466688", agari:"8", tumo: true)

# y = YakuIdentifier.new(menzen: "東 南 西 北 白 發 中 一 九 ① ⑨  9 9", agari:"1")
# y = YakuIdentifier.new(menzen: "456 ④ ⑤ ⑥  四 五 六78 ⑨⑨", agari:"9", furou: [], tumo: true)
# y = YakuIdentifier.new(menzen: "東東 23456", furou: ["8888", "7777*"], agari:"7", zifon: 3, chanfon: 1)
# y = YakuIdentifier.new(menzen: "11223344一 二 三① ② ", agari:"③", zifon: 3, chanfon: 1, dora_count: 5)
# y = YakuIdentifier.new(menzen: "11223344一 二 三① ② ", agari:"③", zifon: 3, chanfon: 1, dora_count: 5)
# y = YakuIdentifier.new(menzen: "112233445577③ ", agari:"③", zifon: 3, chanfon: 1)
# y.run

# binding.pry

# samples = CacheGenerator.get_combinations(max_tiles: 14).sample(10)
# samples.each {|s| p s; puts "\n"; pp GeneralGrouper.group(menzen: s.join(""), furou: [], return_one: false); puts "\n\n\n" }
