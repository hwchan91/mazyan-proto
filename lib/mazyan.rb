require 'pry'

class Pai
  attr_reader :suit, :number, :character

  class InvalidCharacterError < StandardError
  end

  class CannotInitializeError < StandardError
  end

  TILES = {
    "字" => %w(東 南 西 北 白 發 中),
    "萬" => %w(一 二 三 四 五 六 七 八 九),
    "筒" => %w(① ② ③ ④ ⑤ ⑥ ⑦ ⑧ ⑨),
    "索" => %w(1 2 3 4 5 6 7 8 9)
  }

  class << self
    def lookup_table
      @@lookup_table ||= TILES.each_with_object({}) do |(kind, characters), h|
        characters.each_with_index do |character, i|
          h[character] = [kind, i + 1]
        end
      end
    end

    def convert_characters(characters)
      characters = characters.scan(/\w/)
      characters.map { |c| Pai.new(character: c) }
    end
  end

  def initialize(character: nil, suit: nil, number: nil)
    return initialize_by_character(character) if character
    return initialize_by_suit_and_number(suit, number) if suit && number
    raise CannotInitializeError
  end

  def initialize_by_character(character)
    @character = character
    @suit, @number = self.class.lookup_table[character]
    raise InvalidCharacterError unless @suit
  end

  def initialize_by_suit_and_number(suit, number)
    raise CannotInitializeError unless number.between?(1,9)
    @suit, @number = suit, number
    @character = TILES[suit.to_s][number - 1] rescue nil
    raise CannotInitializeError unless @character
  end
end

class Group
  attr_reader :kind, :suit, :number, :is_complete, :is_furou

  def initialize(params)
    @kind          = params[:kind] # 刻順槓嵌
    @suit          = params[:suit]
    @number        = params[:number]
    @is_complete   = params[:is_complete]
    @is_furou      = params[:is_furou] || false

    @is_complete = true if @is_complete.nil?
  end

  def get_machi
    return if is_complete

    case kind
    when "刻" then get_kotu_machi
    when "順" then get_jun_machi
    when "嵌" then get_kanchan_machi
    end
  end

  def get_kotu_machi
    [Pai.new(suit: suit, number: number)]
  end

  def get_jun_machi
    before, after = number - 1, number + 2
    machi = []
    machi << Pai.new(suit: suit, number: before) if before >= 1
    machi << Pai.new(suit: suit, number: after)  if after <= 9
    machi
  end

  def get_kanchan_machi
    [Pai.new(suit: suit, number: number + 1)]
  end

  class << self
    def group_pais(pais: nil, suit: nil, numbers: nil, allow_incomplete: false, allow_kan: false)
      unless suit && numbers
        suits, numbers = pais.map(&:suit), pais.map(&:number)
        return unless all_same?(suits)
        suit = suits.first
      end

      num_of_pais = numbers.size
      return unless num_of_pais.between?(2, 3) || (num_of_pais == 4 && allow_kan)

      return group_same(suit, numbers.first, num_of_pais) if all_same?(numbers)

      return unless suit != '字' && num_of_pais.between?(2, 3)
      numbers = numbers.sort
      return group_consecutive(suit, numbers.first, num_of_pais) if is_consecutive?(numbers)

      return unless num_of_pais == 2 && is_kanchan?(numbers)
      group_kanchan(suit, numbers.first)
    end

    def all_same?(arr)
      arr.uniq.size == 1
    end

    def group_same(suit, number, num_of_pais)
      case num_of_pais
      when 4
        Group.new(kind: "槓", suit: suit, number: number)
      when 3
        Group.new(kind: "刻", suit: suit, number: number)
      when 2
        Group.new(kind: "刻", suit: suit, number: number, is_complete: false)
      else
        nil
      end
    end

    def is_consecutive?(numbers)
      (0...numbers.size - 1).all? { |i| numbers[i] + 1 == numbers[i + 1] }
    end

    def group_consecutive(suit, number, num_of_pais)
      case num_of_pais
      when 3
        Group.new(kind: "順", suit: suit, number: number)
      when 2
        Group.new(kind: "順", suit: suit, number: number, is_complete: false)
      else
        nil
      end
    end

    def is_kanchan?(numbers)
      a, b = numbers
      a + 1 == b - 1
    end

    def group_kanchan(suit, number)
      Group.new(kind: "嵌", suit: suit, number: number, is_complete: false)
    end
  end
end

class NumGrouper
  FORMATIONS = [
    { type: :kotu,    symbol: "刻", category: :mentu , method: :same },
    { type: :jun,     symbol: "順", category: :mentu , method: :sequence },
    { type: :toitu,   symbol: "対", category: :kouhou, method: :same },
    { type: :tatu,    symbol: "塔", category: :kouhou, method: :sequence },
    { type: :kanchan, symbol: "嵌", category: :kouhou, method: :kanchan },
  ]

  class << self
    def initialize_tally
      {
        mentu:   [],
        kouhou:  [],
        isolated: [],
        zyantou: false
      }
    end

    def group(numbers, tally = initialize_tally) # sorted
      num_of_tiles = numbers.size
      return tally if num_of_tiles.zero?

      first = numbers[0]
      return tally_with_category(tally, :isolated, first) if num_of_tiles == 1
      return group(numbers[1..-1], tally_with_category(tally, :isolated, first)) if first_is_isolated?(first, numbers)

      tallies = FORMATIONS.each_with_object([]) do |formation, arr|
        grouped = group_formation(formation, first, numbers, num_of_tiles, tally)
        arr << grouped if grouped
      end

      best_tally(tallies, num_of_tiles)
    end

    def group_formation(formation, first, numbers, num_of_tiles, tally)
      type         = formation[:type]
      symbol       = formation[:symbol]
      category     = formation[:category]
      num_to_group = get_num_to_group(category)
      method       = formation[:method]

      grouped, remaining = send("group_#{method}", first, numbers, num_of_tiles, num_to_group)
      group(remaining, tally_with_category(tally, category, [grouped, "#{symbol}#{first}"], type == :toitu)) if grouped
    end

    def get_num_to_group(category)
      category == :mentu ? 3 : 2
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
      tally[:zyantou] = true if zyantou
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

    def best_tally(tallies, num_of_tiles)
      max_mentu = num_of_tiles / 3
      scores = tallies.map { |t| score(t, max_mentu) }
      tallies[scores.index(scores.min)]
    end

    def score(tally, max_mentu)
      mentu, kouhou, zyantou = tally[:mentu].size, tally[:kouhou].size, tally[:zyantou] ? 1 : 0
      8 - 2 * mentu - [max_mentu - mentu, kouhou - zyantou].min - zyantou
    end
  end
  binding.pry
end


class Hand
  def initialize(monzen, furou)

  end

  def display
  end
end

class Mazyan
  def self.display(monzen, furou = [])
  end
end
