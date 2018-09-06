# TODO: Write documentation for `Trello`

require "ncurses"
require "./*"

module Trello
  VERSION = "0.2.0"

  def self.start
    LibNCurses.setlocale(0, "") # enable unicode
    NCurses.open do
      NCurses.start_color
      # NCurses.use_default_colors
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
        if key == NCurses::KeyCode::RESIZE
          App.windows.each { |w| w.resize }
        else
          App.active_window.handle_key(key)
        end

        NCurses.refresh
        App.windows.select { |w| w.visible }.each { |w| w.refresh }
      end
    end
  end
end

if !File.exists?("#{App::CONFIG_DIR}/secrets.json")
  App.run_setup
end

App.init
Trello.start unless ENV.fetch("CRYSTAL_ENV", nil) == "test"
