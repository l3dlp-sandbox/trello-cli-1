require "ncurses"
require "./window"
require "./help_window"
require "./app"
require "./card_action_builder"
require "./api"

class DetailsWindow < Window
  property row : Int32 = 0

  def initialize(@card : CardDetail)
    initialize(x: 27, y: 1, height: 5, width: NCurses.maxx - 28) do |win|
      win.title = card.name
    end
    App.windows << self
  end

  def initialize(x : Int32, y : Int32, height : Int32, width : Int32, &block)
    initialize(x: x, y: y, height: height, width: width)
    yield self
  end

  def resize
    @width = NCurses.maxx - 28
    @win.resize(height: @height, width: @width)
  end

  def refresh
    @win.erase
    @win.border
    @win.attron(NCurses::Attribute::BOLD | App::Colors.blue)
    @win.mvaddstr(title, x: 1, y: 1)
    @win.attroff(NCurses::Attribute::BOLD | App::Colors.blue)
    @win.mvaddstr("Users: #{@card.member_usernames}", x: 1, y: 2)
    @win.mvaddstr("Labels: #{@card.label_names}", x: 1, y: 3)
    @win.refresh

    NCurses::Pad.open(height: 1000, width: @width - 2) do |pad|
      wrap(@card.description, @width - 2).each_line.with_index do |line, i|
        pad.mvaddstr(line.rstrip, x: 0, y: i)
      end

      if @card.attachments.size > 0
        pad.attron(App::Colors.green)
        pad.addstr(section_header("Attachments"))
        pad.attroff(App::Colors.green)
        @card.attachments.each do |attachment|
          pad.addstr("#{attachment["name"].to_s}\n")
        end
      end

      @card.checklists.each do |checklist|
        pad.attron(App::Colors.green)
        pad.addstr(section_header(checklist["name"].to_s))
        pad.attroff(App::Colors.green)
        checklist["checkItems"].as_a.each do |item|
          if item.as_h["state"].to_s == "complete"
            pad.addstr("[x] ")
          else
            pad.addstr("[ ] ")
          end
          pad.addstr("#{item.as_h["name"].to_s}\n")
        end
      end

      pad.attron(App::Colors.green)
      pad.addstr(section_header("Activity"))
      pad.attroff(App::Colors.green)
      @card.activities.map { |activity| CardActionBuilder.run(activity) }.each do |activity|
        activity.display!(pad, width: @width - 2)
      end
      pad.refresh(@row, 0, 6, 28, NCurses.maxy - 3, NCurses.maxx - 2)
    end
  end

  def handle_key(key)
    case key
    when NCurses::KeyCode::LEFT, 'q', 'h'
      @win.erase
      @win.close
      activate_parent!
      App.remove_window(self)
    when NCurses::KeyCode::UP, 'k'
      @row -= 1
      if @row < 0
        @row = 0
      end
    when NCurses::KeyCode::DOWN, 'j'
      @row += 1
    when 'c'
      @card.add_comment
    when 'd'
      @row += 10
    when 'u'
      @row -= 10
      if @row < 0
        @row = 0
      end
    when ' '
      @card.add_or_remove_self_as_member
    when 76, 'L'
      LabelSelectWindow.new(board_id: @card.board_id) do |win|
        win.link_parent(self)
        win.on_select = ->(label_id : String) do
          @card.manage_label(label_id)
          return
        end
      end
    when 'o'
      `open #{@card.short_url}`
    when 'r'
      reload_card!
    when 'i'
      Popup.new(width: (NCurses.maxx / 1.5).to_i) do |popup|
        popup.link_parent(self)
        popup.text = "GitHub Markdown link:\n![](https://github.trello.services/images/mini-trello-icon.png)\n[#{@card.name}](#{@card.short_url})"
      end
    when 'm'
      ListSelectWindow.new(board_id: @card.board_id) do |win|
        win.link_parent(self)
        win.on_select = ->(list_id : String) do
          @card.move_to_list(list_id)
          return
        end
      end
    when 'a'
      AttachmentSelectWindow.new(card_id: @card.id) do |win|
        win.link_parent(self)
        win.on_select = ->(attachment_url : String) do
          `open #{attachment_url}`
          return
        end
      end
    when 'A'
      @card.add_attachment
    when 'x'
      @card.archive
    when '?'
      HelpWindow.new do |win|
        win.link_parent(self)
        win.add_help(key: "a", description: "Open an attachment in your browser")
        win.add_help(key: "A", description: "Add an attachment URL to this card")
        win.add_help(key: "c", description: "Add a comment to the file via your $EDITOR (CLI only)")
        win.add_help(key: "SPACE", description: "Add or remove yourself as a member of this card")
        win.add_help(key: "shift-l", description: "Add or remove a label to/from this card")
        win.add_help(key: "m", description: "Move this card to another list")
        win.add_help(key: "x", description: "Archive card")
        win.add_help(key: "o", description: "Open this card in your web browser")
        win.add_help(key: "r", description: "Refresh the details")
        win.add_help(key: "i", description: "Show further information about this card")
        win.add_help(key: "j", description: "Scroll down")
        win.add_help(key: "k", description: "Scroll up")
        win.add_help(key: "h", description: "Go back")
      end
    end
  end

  def activate!
    super
    reload_card!
  end

  def reload_card!
    @card.fetch
  end

  def section_header(text)
    "\n\n--|   #{text}   |--\n"
  end
end
