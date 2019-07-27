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

class Grouper
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
      tiles = numbers.size
      return tally if tiles.zero?
      return tally_with_isolated(tally, numbers) if tiles == 1

      first = numbers[0]
      return group(numbers[1..-1], tally_with_isolated(tally, [first])) if first_is_isolated?(first, numbers)

      tallies = []
      kotu, kotu_remaining = group_kotu(first, numbers, tiles)
      tallies << group(kotu_remaining, tally_with_mentu(tally, kotu)) if kotu

      jun, jun_remaining = group_jun(first, numbers, tiles)
      tallies << group(jun_remaining, tally_with_mentu(tally, jun)) if jun

      toitu, toitu_remaining = group_toitu(first, numbers, tiles)
      tallies << group(toitu_remaining, tally_with_kouhou(tally, toitu, true)) if toitu

      tatu, tatu_remaining = group_tatu(first, numbers, tiles)
      tallies << group(tatu_remaining, tally_with_kouhou(tally, tatu)) if tatu

      kanchan, kanchan_remaining = group_kanchan(first, numbers, tiles)
      tallies << group(kanchan_remaining, tally_with_kouhou(tally, kanchan)) if kanchan

      best_tally(tallies, tiles)
      # tallies
    end

    def best_tally(tallies, tiles)
      max_mentu = tiles / 3
      scores = tallies.map { |t| score(t, max_mentu) }
      tallies[scores.index(scores.min)]
    end

    def score(tally, max_mentu)
      mentu, kouhou, zyantou = tally[:mentu].size, tally[:kouhou].size, tally[:zyantou] ? 1 : 0
      8 - 2 * mentu - [max_mentu - mentu, kouhou - zyantou].min - zyantou
    end

    def tally_with_isolated(tally, isolated)
      tally = tally_copy(tally)
      tally[:isolated] << isolated
      tally
    end

    def tally_with_mentu(tally, mentu)
      tally = tally_copy(tally)
      tally[:mentu] << mentu
      tally
    end

    def tally_with_kouhou(tally, kouhou, new_zyantou = false)
      tally = tally_copy(tally)
      tally[:kouhou] << kouhou
      tally[:zyantou] = true if new_zyantou
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

    def first_is_isolated?(first, numbers)
      numbers[1] - first > 2
    end

    def group_kotu(first, numbers, tiles)
      return if tiles < 3
      return unless first == numbers[1] && first == numbers[2]
      [numbers[0..2], numbers[3..-1]]
    end

    def group_jun(first, numbers, tiles)
      return if tiles < 3 || first >= 8
      return unless numbers.include?(first + 1) && numbers.include?(first + 2)
      jun = (first..first + 2).to_a
      [jun, get_remaining(numbers, jun)]
    end

    def group_toitu(first, numbers, tiles)
      return unless first == numbers[1]
      [numbers[0..1], numbers[2..-1]]
    end

    def group_tatu(first, numbers, tiles)
      return if first == 9
      return unless numbers.include?(first + 1)
      tatu = [first, first + 1]
      [tatu , get_remaining(numbers, tatu)]
    end

    def group_kanchan(first, numbers, tiles)
      return if first >= 8
      return unless numbers.include?(first + 2)
      kanchan = [first, first + 2]
      [kanchan, get_remaining(numbers, kanchan)]
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
