

fooCls = objc.class('FooObj')
alice = fooCls:alloc():initWithName('Alice')
-- print('name:', alice.name)
tbl = { person=alice, age=28, gender='F' }
print(objc.tostring(tbl))