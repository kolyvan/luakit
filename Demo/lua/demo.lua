
function theApp()
	return objc.class('UIApplication'):sharedApplication().delegate
end

function navVC()
	return theApp().window.rootViewController
end

function topVC()
	return navVC().topViewController
end

k = {}

r_k = objc.mkref(k) -- for table delegate and button action

k.addButton = function(vc)	
	local blueColor = objc.class('UIColor'):blueColor()
	local whiteColor = objc.class('UIColor'):whiteColor()
	
	local v = vc.view
	local _,_,w,h = objc.unpack(v.bounds)
	local btn = objc.class('UIButton'):buttonWithType(1)
	
	btn.frame = objc.cgrect((w-100)*0.5,(h-60)*0.5,100,50)	
	btn.backgroundColor = objc.class('UIColor'):blueColor()
	btn:setTitleColor_forState(whiteColor, 0)
	btn:setTitle_forState('PUSH', 0)
	btn:addTarget_action_forControlEvents(r_k, 'buttonDidPress', 2^6)
	v:addSubview(btn) 	

	objc.sweep(btn)		
	objc.sweep(v)			
end

k.pushTable = function()
	local tvc = objc.create('ChildTableViewController', 'initWithStyle', 0)
	
	tvc.title = 'Lua Table'
	navVC():pushViewController_animated(tvc, true)
    r_k:adoptsProtocol('UITableViewDelegate')
    r_k:adoptsProtocol('UITableViewDataSource')
	tvc.view.delegate = r_k
	tvc.view.dataSource = r_k	
	
	objc.sweep(tvc)	
end

k.buttonDidPress = function()	
	k.pushTable()
end

k.numberOfSectionsInTableView = function(table)	
	return 1
end

k.tableView_numberOfRowsInSection = function(table, section)	
	return 10
end

k.tableView_cellForRowAtIndexPath = function(table, index)	
	local cell = table:dequeueReusableCellWithIdentifier('Cell')	
	if nil == cell then
		cell = objc.alloc('UITableViewCell'):initWithStyle_reuseIdentifier(0, 'Cell')				
	end	
	local lbl = cell.textLabel
	lbl.text = 'Row #'..index.row
	objc.sweep(lbl)	
	return cell
end

k.tableView_didSelectRowAtIndexPath = function(table, index)
	table:deselectRowAtIndexPath_animated(index, true)
	print('selected', index.row)
end

function main()
	k.addButton(topVC())
end

main()