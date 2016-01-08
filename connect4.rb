# tConnect 4 Freeware version w/ Network Support
# 

require 'tk'
require 'xmlrpc/client'
require 'xmlrpc/server'

module CountConnected
	def connected(board,owner,curr_piece_coord,connect_length)
		raise 'Wrong data type for board' unless board.instance_of? Array
		raise 'Wrong data type for board' unless (board[0]).instance_of? Array
		raise 'Wrong data type for board' unless (board[0][0]).instance_of? Hash
		raise 'Wrong data type for coord' unless curr_piece_coord.instance_of? Hash
		raise 'Wrong data type for connect length' unless connect_length.integer?

		rows = board.size
		cols = board[0].size
	
		row_start = curr_piece_coord['row'] - 3
		row_end = curr_piece_coord['row'] + 3
		row_start = 0 if row_start < 0
		row_end = rows - 1 if row_end >= rows
		
		col_start = curr_piece_coord['col'] - 3
		col_end = curr_piece_coord['col'] + 3
		col_start = 0 if col_start < 0
		col_end = cols - 1 if col_end >= cols
		
		num_connected = 0

		row_start.upto(row_end) {|i|
			(board[i][curr_piece_coord['col']])['owner'] == owner ? num_connected += 1 : num_connected = 0
			break if num_connected >= connect_length
		}
		
		num_connected = 0 if num_connected < connect_length
		col_start.upto(col_end) {|j|
			(board[curr_piece_coord['row']][j])['owner'] == owner ? num_connected += 1 : num_connected = 0
			break if num_connected >= connect_length
		} unless num_connected >= connect_length
		
		row_start = curr_piece_coord['row']
		col_start = curr_piece_coord['col']
		while row_start > 0 and col_start > 0
			row_start -= 1
			col_start -= 1
		end		
		row_end = curr_piece_coord['row']
		col_end = curr_piece_coord['col']
		while row_end < rows-1 and col_end < cols-1
			row_end += 1
			col_end += 1
		end
		
		num_connected_diag1 = 0
		0.upto(row_end - row_start) {|i|
			if row_start+i < rows and col_start+i < cols
				(board[row_start+i][col_start+i])['owner'] == owner ? num_connected_diag1 += 1 : num_connected_diag1 = 0
			end
			break if num_connected_diag1 >= connect_length
		} unless num_connected >= connect_length
		
		row_start = curr_piece_coord['row']
		col_start = curr_piece_coord['col']
		while row_start < rows-1 and col_start > 0
			row_start += 1
			col_start -= 1
		end
		row_end = curr_piece_coord['row']
		col_end = curr_piece_coord['col']
		while row_end > 0 and col_end < cols-1
			row_end -= 1
			col_end += 1
		end
		
		num_connected_diag2 = 0
		0.upto(col_end - col_start) {|i|
			if row_start-i >= 0 and col_start+i < cols
				(board[row_start-i][col_start+i])['owner'] == owner ? num_connected_diag2 += 1 : num_connected_diag2 = 0
			end
			break if num_connected_diag2 >= connect_length
		} unless num_connected >= connect_length or num_connected_diag1 >= connect_length
		
		if num_connected >= 4 or num_connected_diag1 >= 4 or num_connected_diag2 >= 4
			true
		else
			false
		end
	end
end

# getting list of hosts module
module HostList
	def get_hosts
		host_list = Array.new
		File.open('/etc/hosts', 'r') do |aFile|
			line = aFile.gets
			while line
				host_list << (line.split(' '))[0]
				line = aFile.gets
			end # while
		end # file block
		host_list
	end
end


# Main game network module
module Connect4NetworkLib
	def scan_hosts
		begin
			host_list = get_hosts
		rescue
			host_list = nil
		end
		
		server_list = Array.new
		threads = Array.new
		
		host_list.each { |host|
			server_raw = XMLRPC::Client.new(host, '/RPC2',@port)
			server = server_raw.proxy('opponent')
			threads << Thread.new(server,host) { |aServer,aHost|
				begin
					Thread.current['name'] = aServer.game_up?
				rescue
					Thread.current['name'] = false
				ensure
					Thread.current['ip'] = aHost
				end
			}
		}
		threads.each {|t| t.join} 
		threads.each {|t| server_list << {'name'=> t['name'], 'ip'=> t['ip']} if (t['name']) }
		if ARGV[0] == 'debug'
			 print 'active server list ' 
			 p server_list
		end
		server_list
	end
	
	def request_game(server_id)
		if server_id == nil
			popup_msg('No server selected.', 'ok', 'Server Error', 'error')
		else
			server_raw = XMLRPC::Client.new((@server_list[server_id])['ip'], '/RPC2',@port)
			server = server_raw.proxy('opponent')
			begin
				if (server.game_open?({'name'=>@my_name, 'ip'=>@my_ip}))
					@opponent_info['name'] = (@server_list[server_id])['name']
					@opponent_info['ip'] = (@server_list[server_id])['ip']
					@toplevel.destroy
					draw_board
					setup_communication
					@connected = true
				else
					popup_msg('Server has declined to let you play. Please select another one.', 'ok', 'Server Error', 'error')
				end
			rescue
				popup_msg('Server is not responding. Please select another one.', 'ok', 'Server Error', 'error')
			end # exception
		end # if
	end
	
	def setup_communication
		p 'my_ip: ' + @my_ip if ARGV[0] == 'debug'
		if @my_turn == 'p1'
			@s = XMLRPC::Server.new(@port, @my_ip)
		else
			@s = XMLRPC::Server.new(@port+1, @my_ip)
			@server_raw = XMLRPC::Client.new(@opponent_info['ip'], '/RPC2',@port)
			@server = @server_raw.proxy('opponent')
		end
		
		@s.add_handler("opponent.talk") do |owner,msg| 
			insert_text(owner,msg)
			true
		end
		@s.add_handler("opponent.request_rematch") do
			request_rematch
		end
		@s.add_handler("opponent.drop_piece") do |col| 
			drop_piece(col)
			true
		end
		
		@s.add_handler("opponent.disconnect") do 
			disconnected
			true
		end
		
		if @my_turn == 'p1'
			@s.add_handler("opponent.game_up?") do 
				@connected ? false : @my_name
			end
			@s.add_handler("opponent.game_open?") do |opponent_info|
				game_open?(opponent_info)
			end
		end
		@server_thread = Thread.new(@s) { |server| server.serve }
	end
	
	def game_open?(opponent_info)
		return false if @connected
		
		if popup_msg("#{opponent_info['name']} has requested a match.  Do you accept this challenge?", 'yesno', 'Match Request', 'question') == 'yes'
			@opponent_info['name'] = opponent_info['name']
			@opponent_info['ip'] = opponent_info['ip']
			@server_raw = XMLRPC::Client.new(@opponent_info['ip'], '/RPC2',@port+1)
			@server = @server_raw.proxy('opponent')
			@connected = true
			insert_text('---system---',"#{opponent_info['name']} has joined the game.")
			true
		else
			false
		end
	end
	
	def disconnected
		@connected = false
		if @my_turn == 'p1'
			insert_text('---system---', "#{@opponent_info['name']} has disconnected!")
			new_game
		else
			popup_msg('Your opponent has disconnected!', 'ok', 'Connection Error', 'error')
			@toplevel.destroy
			setup_join
		end
	end
	
	def server_listings
		begin
			@server.disconnect if @connected
		rescue
		
		end
		
		@connected = false
		@toplevel.destroy
		setup_join
	end
	
	def i_quit
		begin
			@server.disconnect if @connected
		rescue
		
		end
		exit
	end
	
	def chat
		if @connected
			insert_text('<'+@my_name+'>', @chatinput_text.value)
			begin
				@server.talk('<'+@my_name+'>', @chatinput_text.value)
			rescue 
				disconnected
			end
			@chatinput_text.value = ''
		end
	end
	
	def send_rematch_request
		@accept_rematch_request = true
		server_reply = 'no'
		begin
			server_reply = @server.request_rematch
  	rescue
  		disconnected
		end
		if server_reply == 'yes'
			new_game
		else
			popup_msg("#{@opponent_info['name']} has declined your challenge", 'ok', 'Rematch Request',  'info')
		end
		@accept_rematch_request = false
	end
	
	def request_rematch
		if @accept_rematch_request == true
			new_game
			return 'yes'
		end
		if popup_msg("#{@opponent_info['name']} has requested a rematch.  Do you accept this challenge?", 'yesno', 'Rematch Request', 'question') == 'yes'
			new_game
			return 'yes'
		else
			return 'no'
		end
	end
end

# Main game engine/GUI (reused from as4)
class Connect4
	include CountConnected
	include HostList
	include Connect4NetworkLib
	
	EXPECTED_METHODS_C4N = ['send_rematch_request', 'i_quit', 'scan_hosts', 'request_rematch', 'request_game', 'server_listings', 'disconnected', 'game_open?', 'insert_text', 'setup_communication', 'chat']
	
	def initialize
		@rows = 6
		@cols = 7
		@gameover = false
		@turn = 'p1'
		@port = 3333
		@opponent_info = Hash.new
		@connected = false
		@my_ip = ENV['HOST']
		@single_mode = false
		
		(Connect4NetworkLib.public_instance_methods).each { |aMethod| raise 'Missing method from module Connect4NetworkLibs' if EXPECTED_METHODS_C4N.index(aMethod) == nil }
	
		draw_main
		
		# draw_board
	end
	
	# def main_screen
	# 	begin
	# 		@server.disconnect if @connected
	# 		Thread.kill(@server_thread)
	# 		rescue
		
	# 	end
	# 	@turn = 'p1'
	# 	@gameover = false
	# 	@toplevel.destroy
	# 	draw_main
	# end
	
	
	
	def setup_host
		p 'host mode' if ARGV[0] == 'debug'
		
		if @name_input.value == '' then 
			Tk.messageBox('message'=> 'You have entered an invalid name.', 'type'=> 'ok', 'title'=> 'Name Error', 'icon'=> 'error')
		else
			@gameover = false
			@turn = 'p1'
			@my_name = @name_input.value
			@my_turn = 'p1'
			setup_communication
			@toplevel.destroy
			draw_board
			
			insert_text('---system---','Waiting for a player to join...')
		end # if
	end
	
	def setup_join
		p 'join mode' if ARGV[0] == 'debug'
		
		if @name_input.value == '' then 
			Tk.messageBox('message'=> 'You have entered an invalid name.', 'type'=> 'ok', 'title'=> 'Name Error', 'icon'=> 'error')
		else
			@gameover = false
			@turn = 'p1'
			@my_name = @name_input.value
			@my_turn = 'p2'
			setup_communication
			@toplevel.destroy
			draw_server_list
		end # if
	end
	
	def setup_single
		p 'single mode' if ARGV[0] == 'debug'
	
		@rows = 6
		@cols = 7
		@ai_level = 1
		@ai_player = 'p2'
		@opponent_info = {'name'=>'Computer', 'ip'=>nil}
		@gameover = false
		@turn = 'p1'
		@single_mode = true
		@my_name = 'Player1'
		@my_turn = 'p1'
		@toplevel.destroy
		draw_board
	end
	
	def new_game
		@turn = 'p1'
		if @single_mode == true
			@my_turn = 'p1'
			@ai_level > 0 ? @gamemode.configure('text'=>'Mode: vs Computer') : @gamemode.configure('text'=>'Mode: vs Human')
		end
		@gameover = false
		@board.each { |row| 
			row.each { |element|
				if element['owner'] != nil
					element['owner'] = nil
					element['img'].configure('image'=> @img_none)
				end
			}
		}
	end

	def new_piece(col)
		if @turn == @my_turn and @gameover == false and @connected
			begin
				t = Thread.new(@server) {|server| server.drop_piece(col) }
				drop_piece(col)
				t.join
			rescue
				disconnected
			end
			
		elsif @single_mode == true
			drop_piece(col)
			if @turn == @ai_player and @ai_level > 0 and @gameover == false
				col = computer_move
				drop_piece(col)
			end
		end
	end

	def drop_piece(col)
		row = find_row(@board,col)
		if row and @gameover == false
			img_to_change = @board[row][col]
			img_to_change['owner'] = @turn
			@curr_piece_coord = {'row'=> row, 'col'=> col}
			(@turn == 'p1') ? img_to_change['img'].configure('image'=> @img_p1) : img_to_change['img'].configure('image'=> @img_p2)

			game_end = game_end?(@board, @turn, @curr_piece_coord)
			if game_end
				@gameover = true
				if game_end == 'tie'
					Tk.messageBox('message'=> 'Tie game!', 'type'=> 'ok', 'title'=> 'Gameover')
				else
					if @turn == @my_turn
						Tk.messageBox('message'=> "#{@my_name} won!", 'type'=> 'ok', 'title'=> 'Gameover')
					else
						Tk.messageBox('message'=> "#{@opponent_info['name']} won!", 'type'=> 'ok', 'title'=> 'Gameover')
					end
				end
			end
			(@turn == 'p1') ? @turn = 'p2' : @turn = 'p1'
		end # rows check
	end

	def game_end? (board, turn, curr_piece_coord)
		if connected(board,turn,curr_piece_coord,4)
			p 'whose turn: '+turn if ARGV[0] == 'debug'
			turn
		else
			not_empty = false
			0.upto(@cols-1) {|col|
				if find_row(@board,col)
					not_empty = true
					break
				end
			}
			not_empty == true ? nil : 'tie'
		end
	end
	
	def computer_move
		@turn == 'p1' ? next_turn = 'p2' : next_turn = 'p1'
		temp_board = @board.map {|i| i.map {|j| j.dup}}
		col_to_drop = -1
		0.upto(@cols - 1) {|col|
			row = find_row(temp_board,col)
			if row
				(temp_board[row][col])['owner'] = @turn
				if game_end?(temp_board,@turn,{'row'=> row, 'col'=> col}) == @turn
					col_to_drop = col
					break
				end
				(temp_board[row][col])['owner'] = next_turn
				if game_end?(temp_board,next_turn,{'row'=> row, 'col'=> col}) == next_turn
					col_to_drop = col
				end
				(temp_board[row][col])['owner'] = nil
			end
		}
		
		total_free_slots = 0
		col_array = Array.new
		0.upto(@cols - 1) {|col| col_array << col}
		
		while col_array.length > 0 and col_to_drop < 0
			col = col_array[rand(col_array.length)]
			col_array.delete(col)
			max_slot_free = rows_free(@board,col)
			total_free_slots += max_slot_free
			if max_slot_free > 1
				(temp_board[@rows-max_slot_free][col])['owner'] = @turn
				(temp_board[@rows-max_slot_free+1][col])['owner'] = next_turn
				if game_end?(temp_board,next_turn,{'row'=>(@rows-max_slot_free+1),'col'=>col}) == nil
					col_to_drop = col
					break
				end
			elsif max_slot_free == 1
				col_to_drop = col
			end # end big if-else block
		end # end while

		0.upto(@cols - 1) {|col| col_to_drop = col if rows_free(@board,col) > 0 } if col_to_drop < 0 and total_free_slots <= 2 and total_free_slots > 0
		col_to_drop = rand(@cols) if col_to_drop < 0 
		loop {
			break if rows_free(@board,col_to_drop) > 0
			col_to_drop = rand(@cols)
		}
		col_to_drop
	end

	def rows_free(board,col)
		num_free = 0
		0.upto(@rows-1) {|row| num_free += 1 if (board[row][col])['owner'] == nil}
		num_free
	end
		
	def find_row(board, col)
		board.index(board.find {|row| (row[col])['owner'] == nil})
	end
	
	
	def draw_main
		@root = TkRoot.new() {title 'tConnect 4'}
		@toplevel = TkFrame.new(@root).pack
		text_frame = TkFrame.new(@toplevel).pack('side'=>'top', 'fill'=> 'x', 'expand'=> true)
		input_frame = TkFrame.new(@toplevel).pack('side'=>'top', 'fill'=> 'x')
		button_frame = TkFrame.new(@toplevel).pack('side'=>'top', 'fill'=> 'x')

		TkMessage.new(text_frame, 'text'=> 'Please enter your name and choose whether you want to host or find a game or play a single player game.', 'width'=> 330).pack('side'=>'left')
		TkLabel.new(input_frame, 'justify'=> 'left', 'text'=> 'Name: ').pack('side'=>'left')
		@name_input = TkVariable.new
		TkEntry.new(input_frame, 'justify'=> 'left', 'textvariable'=> @name_input).pack('side'=>'left', 'expand'=> true, 'fill'=> 'x')
		TkButton.new(button_frame, {'text'=> 'Host Game', 'command'=> proc {self.setup_host} }).pack('side'=> 'left')
		TkButton.new(button_frame, {'text'=> 'Find Games', 'command'=> proc {self.setup_join} }).pack('side'=> 'left')
		TkButton.new(button_frame, {'text'=> 'Single Player Mode', 'command'=> proc {self.setup_single} }).pack('side'=> 'left')
	end

	def draw_server_list
		@root = TkRoot.new() {title 'tConnect 4 Server Listings'}
		@toplevel = TkFrame.new(@root).pack
		TkLabel.new(@toplevel, 'justify'=> 'left', 'text'=> 'Select a game you would like to join.').pack('side'=>'top')


		list_frame = TkFrame.new(@toplevel).pack('side'=>'left', 'fill'=>'y')
		listbox = TkListbox.new(list_frame, 'selectmode'=> 'single').pack('side'=>'left', 'fill'=>'both', 'expand'=>true)


		@server_list = scan_hosts
		@server_list.each { |server| listbox.insert('end', server['name']) }

		bar = TkScrollbar.new(list_frame).pack('side'=>'right', 'fill'=>'y')
		listbox.yscrollbar(bar)

		TkButton.new(@toplevel, {'text'=> 'Join Game', 'command'=> proc {request_game(listbox.curselection[0])} }).pack
		refresh_button = TkButton.new(@toplevel,'text'=> 'Refresh List')
		refresh_button.pack
		refresh_button.bind('ButtonRelease-1', proc {
			listbox.delete(0,'end')
			@server_list = scan_hosts
			@server_list.each { |server| listbox.insert('end', server['name']) }
		})
		TkButton.new(@toplevel, {'text'=> 'Quit', 'command'=> proc {exit} }).pack
	end

	def draw_board
		@root = TkRoot.new() {title 'tConnect 4'}
		@toplevel = TkFrame.new(@root).pack
		optionarea = TkFrame.new(@toplevel).pack
		statusbar = TkFrame.new(@toplevel).pack('side'=> 'bottom')
		playarea = TkFrame.new(@toplevel).pack
		@img_none = TkPhotoImage.new('file'=> 'none.gif')
		@img_p1 = TkPhotoImage.new('file'=> 'red.gif')
		@img_p2 = TkPhotoImage.new('file'=> 'yellow.gif')
		@img_highlight = TkPhotoImage.new('file'=> 'highlight.gif')
		@img_no_highlight = TkPhotoImage.new('file'=> 'no_highlight.gif')

		@board = (0..(@rows-1)).map { |i|
			new_row = TkFrame.new(playarea).pack('side'=> 'bottom')
			(0..(@cols-1)).map { |j|
				{'owner'=> nil, 
				 'img'=> TkLabel.new(new_row, {'image'=> @img_none, 'background'=> '#040284'})
				}
			} # col
		} # row
		
		highlight_bar_frame = TkFrame.new(playarea).pack('side'=> 'top')
		@highlight_bar = (0..(@cols-1)).map { |j|	TkLabel.new(highlight_bar_frame, {'image'=> @img_no_highlight, }).pack('side'=>'left')	}
		
		# packing and binding
		@board.each { |row| 
			row.each { |element|
				element['img'].pack('side'=> 'left')
				element['img'].bind('ButtonPress',proc {self.new_piece(row.index(element)) })
				element['img'].bind('Enter', proc {@highlight_bar[row.index(element)].configure('image'=> @img_highlight) })
				element['img'].bind('Leave', proc {@highlight_bar[row.index(element)].configure('image'=> @img_no_highlight) })
			}
		}
		TkButton.new(optionarea, {'text'=> 'New Game', 'command'=> proc {@connected ? self.send_rematch_request : new_game} }).pack('side'=> 'left')
		TkButton.new(optionarea, {'text'=> 'Server Listings', 'command'=> proc {self.server_listings} }).pack('side'=> 'left') if @my_turn == 'p2' and @single_mode == false
		if @single_mode == true
			@gamemode = TkButton.new(optionarea, {'text'=> 'Mode: vs Computer' }).pack('side'=> 'left')
			@gamemode.bind('ButtonPress', proc {
				if @ai_level > 0 then
					@ai_level = 0
					@opponent_info = {'name'=>'Player2', 'ip'=>nil}
					self.new_game
				else
					@ai_level = 1
					@opponent_info = {'name'=>'Computer', 'ip'=>nil}
					self.new_game
				end
			})
		end
		TkButton.new(optionarea, {'text'=> 'Quit', 'command'=> proc {self.i_quit} }).pack('side' => 'left')
		
		if @single_mode == false
			p 'multi player chatbox bindings' if ARGV[0] == 'debug'
			chatbox = TkFrame.new(statusbar).pack('side'=>'top')
			@chatbox   = TkText.new(chatbox, 'height'=> 10, 'width'=> 51).pack('side'=>'left')
			bar = TkScrollbar.new(chatbox).pack('side'=>'right', 'fill'=>'y')
			@chatbox.yscrollbar(bar)
			@chatbox.state('disable')
			@chatinput_text = TkVariable.new
			@chatinput = TkEntry.new(statusbar, 'justify'=> 'left', 'textvariable'=> @chatinput_text).pack('side'=>'bottom', 'fill'=>'x')
			@root.bind('Any-Key-Return', proc { self.chat})
		end
	end
	
	# method for Connect4NetworkLibs to use, so it's not tied to to any gui stuff
	def popup_msg(msg_msg, msg_type,msg_title,msg_icon)
		Tk.messageBox('message'=>msg_msg, 'type'=>msg_type,'title'=>msg_title, 'icon'=>msg_icon)
	end
	
	def insert_text(owner, msg)
		@chatbox.state('normal')
		@chatbox.insert('end',owner+' '+ msg+"\n")
		@chatbox.state('disable')
		@chatbox.see('end')
		true
	end
	
end

game = Connect4.new
Tk.mainloop
