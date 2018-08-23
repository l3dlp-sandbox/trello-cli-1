# TODO: Write documentation for `Trello`

require "ncurses"
require "json"
require "http/client"
require "logger"

module Trello
  VERSION = "0.1.0"

  LOG = Logger.new(File.open("log.txt", "w"), level: Logger::DEBUG)

  class App
    @@windows : Array(Window) = [] of Window

    def self.windows=(windows : Array(Window))
      @@windows = windows
    end

    def self.windows
      @@windows
    end

    module Colors
      extend self
      def cyan
       NCurses::ColorPair.new(1).init(NCurses::Color::CYAN, NCurses::Color::BLACK)
      end
    end
  end

  class API
    SECRETS = JSON.parse(File.read(".secrets.json"))
    API_ROOT = "https://api.trello.com/1/"
    CREDENTIALS = "key=#{SECRETS["key"]}&token=#{SECRETS["token"]}"

    def self.get(path : String, params : String)
      url = "#{API_ROOT}/#{path}?#{CREDENTIALS}&#{params}"
      LOG.debug("Fetching URL: #{url}")
      response = HTTP::Client.get(url)
      json = JSON.parse(response.body)
      LOG.debug("Fetched: #{json}")
      json
    end
  end

  class ListSelectOption
    getter key, value

    def initialize(@key : String, @value : String)
    end
  end

  class CardDetail
    getter name

    def initialize(@id : String, @name : String)
    end
  end

  abstract class Window
    property active : Bool = false
    property title : String = ""

    def initialize(x : Int32, y : Int32, height : Int32, width : Int32)
      @win = NCurses::Window.new(y: y, x: x, height: height, width: width)
      @width = width
      @height = height
    end

    def refresh
      @win.refresh
    end

    def link_parent(parent : Window)
      @parent = parent
      parent.link_child(self)
    end

    def activate_parent!
      # you can't get a truthy value out of an instance variable
      parent = @parent
      if parent
        @active = false
        parent.active = true
      end
    end

    def activate_child!(option)
    end

    def active?
      @active
    end

    def activate!
      @active = true
    end
  end

  class DetailsWindow < Window
    def initialize(@card : CardDetail)
      initialize(x: 27, y: 1, height: NCurses.maxy - 2, width: NCurses.maxx - 28) do |win|
        win.title = card.name
      end
      App.windows << self
    end

    def initialize(x : Int32, y : Int32, height : Int32, width : Int32, &block)
      initialize(x: x, y: y, height: height, width: width)
      yield self
    end

    def refresh
      @win.erase
      @win.border
      @win.attron(App::Colors.cyan.attr)
      @win.mvaddstr(title, x: 2, y: 0)
      @win.attroff(App::Colors.cyan.attr)
      @win.refresh
    end

    def handle_key(key)
      case key
      when NCurses::KeyCode::LEFT, 'q', 'h'
        @win.erase
        @win.close
        activate_parent!
        App.windows.delete(self)
      end
    end
  end

  abstract class ListSelectWindow < Window
    getter win, height, width, title, parent, child, selected, active, json

    setter selected : Int8
    setter active : Bool
    setter title : String
    setter path : String
    setter params : String
    setter options : Array(ListSelectOption)
    setter board_id : String = ""

    property row_offset : Int32 = 0

    WIDTH = 25
    HEIGHT = 15

    def initialize(x : Int32, y : Int32, height : Int32, width : Int32)
      @win = NCurses::Window.new(y: y, x: x, height: height, width: width)
      @selected = 0
      @width = width
      @height = height
      @title = ""
      @active = false
      @path = ""
      @params = ""
      @options = [] of ListSelectOption
    end

    def initialize(x : Int32, y : Int32, height : Int32, width : Int32, &block)
      initialize(x: x, y: y, height: height, width: width)
      yield self
    end

    def refresh
      win.erase
      win.border
      win.mvaddstr(title, x: 2, y: 0)

      y = 0

      @options[@row_offset..height+@row_offset].each_with_index do |option, i|
        if y >= height-2
          break
        end

        win.move(x: 1, y: y+=1)

        if i == @selected
          if @active
            win.attron(NCurses::Attribute::STANDOUT)
          else
            win.attron(NCurses::Attribute::BOLD | App::Colors.cyan.attr)
          end
        end
        win.addnstr(option.value, width-2)
        win.attroff(NCurses::Attribute::STANDOUT)
        win.attroff(NCurses::Attribute::BOLD | App::Colors.cyan.attr)
      end

      win.refresh
    end

    def handle_key(key)
      case key
      when NCurses::KeyCode::DOWN, 'j'
        if @selected < height-3
          @selected += 1
        elsif @row_offset + height <= @options.size + 1
          @row_offset += 1
        end
      when NCurses::KeyCode::UP, 'k'
        if @selected > 0
          @selected -= 1
        elsif @row_offset > 0
          @row_offset -= 1
        end
      when NCurses::KeyCode::RETURN, NCurses::KeyCode::RIGHT, 'l'
        handle_select_next(@options[@selected + @row_offset])
      when NCurses::KeyCode::LEFT, 'q', 'h' # Q, J
        handle_select_previous
      else
        LOG.debug("Unhandled key: #{key}")
      end
    end

    def link_child(child : Window)
      @child = child
    end

    def activate!
      super
      if !@path.empty?
        json = API.get(@path, @params)
        json.as_a.each do |j|
          @options << ListSelectOption.new(key: j.as_h["id"].to_s, value: j.as_h["name"].to_s)
        end
      end
    end

    def handle_select_previous
      @options = [] of ListSelectOption
      @selected = 0
      activate_parent!
    end

    def handle_select_next(selected)
      activate_child!(selected)
    end
  end

  class BoardsWindow < ListSelectWindow
    def initialize
      super(x: 1, y: 1, height: 15, width: 25) do |win|
        win.path = "/members/me/boards"
        win.params = "fields=name,starred,shortUrl"
        win.active = true
        win.title = "Boards"
      end
    end

    def activate_child!(option : ListSelectOption)
      # you can't get a truthy value out of an instance variable
      child = @child
      if child
        @active = false
        child.set_board_id(option.key) if child.is_a? ListsWindow
        child.activate!
      end
    end
  end

  class ListsWindow < ListSelectWindow
    property board_id : String = ""

    def initialize
      super(x: 1, y: 17, height: 15, width: 25) do |win|
        win.title = "Lists"
      end
    end

    def set_board_id(id : String)
      @path = "/boards/#{id}/lists"
      @params = "fields=name,shortUrl"
    end

    def activate_child!(option : ListSelectOption)
      child = @child
      if child
        @active = false
        child.set_list_id(option.key) if child.is_a? CardsWindow
        child.activate!
      end
    end
  end

  class CardsWindow < ListSelectWindow
    property list_id : String = ""

    def initialize
      super(x: 27, y: 1, height: NCurses.maxy - 2, width: NCurses.maxx - 28) do |win|
        win.title = "Cards"
      end
    end

    def set_list_id(id : String)
      @path = "/lists/#{id}/cards"
      @params = "fields=name,shortUrl"
    end

    def handle_select_next(selected)
      card = CardDetail.new(id: selected.key, name: selected.value)

      details = DetailsWindow.new(card: card)
      details.link_parent(self)
      details.activate!
      @active = false
    end
  end

  NCurses.open do
    NCurses.start_color
    NCurses.cbreak # CTRL-C breaks the program
    NCurses.noecho # Don't print characters as the user types
    NCurses.curs_set(0) # hide the cursor
    NCurses.keypad(true) # allows arrow and F# keys

    boards = BoardsWindow.new
    boards.activate!

    lists = ListsWindow.new
    lists.link_parent(boards)

    cards = CardsWindow.new
    cards.link_parent(lists)

    App.windows = [boards, lists, cards] of Window

    NCurses.refresh
    App.windows.each { |w| w.refresh }

    while true
      NCurses.notimeout(true)
      key = NCurses.getch
      active_window = App.windows.find(boards) { |w| w.active }
      active_window.handle_key(key)

      NCurses.refresh
      App.windows.each { |w| w.refresh }
    end
  end
end
