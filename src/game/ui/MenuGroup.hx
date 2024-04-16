package ui;

// import dn.Geom;
// import dn.Lib;

enum abstract MenuDir(Int) {
	var North;
	var East;
	var South;
	var West;
}


@:allow(ui.MenuGroupElement)
class MenuGroup extends dn.Process {
	static var UID = 0;

	var uid : Int;
	var ca : ControllerAccess<GameAction>;
	var current : Null<MenuGroupElement>;

	var elements : Array<MenuGroupElement> = [];
	var connectionsInvalidated = true;
	var connectedGroups : Map<MenuDir, MenuGroup> = new Map();

	var focused = true;


	public function new(p:dn.Process) {
		super(p);
		uid = UID++;
		ca = App.ME.controller.createAccess();
		ca.lockCondition = isControllerLocked;
	}

	function isControllerLocked() {
		return !focused;
	}


	public function registerElement(f,cb) : MenuGroupElement {
		var ge = new MenuGroupElement(this, f,cb);
		elements.push(ge);
		return ge;
	}


	public function focusGroup() {
		var wasFocus = focused;
		focused = true;
		ca.lock(0.2);
		blurAllConnectedGroups();
		if( !wasFocus )
			onGroupFocus();
	}

	public function blurGroup() {
		var wasFocus = focused;
		focused = false;
		if( current!=null ) {
			current.onBlur();
			current = null;
		}
		if( wasFocus )
			onGroupBlur();
	}

	public dynamic function onGroupFocus() {}
	public dynamic function onGroupBlur() {}

	function blurAllConnectedGroups(?ignoredGroup:MenuGroup) {
		var pending = [this];
		var dones = new Map();
		dones.set(uid,true);

		while( pending.length>0 ) {
			var cur = pending.pop();
			dones.set(cur.uid, true);
			for(g in cur.connectedGroups) {
				if( dones.exists(g.uid) )
					continue;
				g.blurGroup();
				pending.push(g);
			}
		}
	}

	inline function invalidateConnections() {
		connectionsInvalidated = true;
	}

	function buildConnections() {
		for(t in elements)
			t.clearConnections();

		// Build connections with closest aligned elements
		for(from in elements)
			for(dir in [North,East,South,West]) {
				var other = findElementRaycast(from,dir);
				if( other!=null )
					from.connectNext(dir,other);
			}

		// Fix missing connections
		for(from in elements)
			for(dir in [North,East,South,West]) {
				if( from.hasConnection(dir) )
					continue;
				var next = findElementFromAng(from, dirToAng(dir), M.PI*0.8, true);
				if( next!=null )
					from.connectNext(dir, next, false);
			}
	}


	// Returns closest Element using an angle range
	function findElementFromAng(from:MenuGroupElement, ang:Float, angRange:Float, ignoreConnecteds:Bool) : Null<MenuGroupElement> {
		var best = null;
		for( other in elements ) {
			if( other==from || from.isConnectedTo(other) )
				continue;

			if( M.radDistance(ang, from.angTo(other)) < angRange*0.5 ) {
				if( best==null )
					best = other;
				else {
					if( from.distTo(other) < from.distTo(best) )
						best = other;
				}
			}
		}
		return best;


	}

	// Returns closest Element using a collider-raycast
	function findElementRaycast(from:MenuGroupElement, dir:MenuDir) : Null<MenuGroupElement> {
		var x = from.left;
		var y = from.top;
		var ang = dirToAng(dir);
		var elapsedDist = 0.;
		var step = switch dir {
			case North, South: from.height;
			case East,West: from.width;
		}

		var possibleNexts = [];
		while( elapsedDist<step*3 ) {
			for( other in elements )
				if( other!=from && dn.Geom.rectTouchesRect(x,y,from.width,from.height, other.left,other.top,other.width,other.height) )
					possibleNexts.push(other);

			if( possibleNexts.length>0 )
				return dn.Lib.findBestInArray(possibleNexts, (t)->-t.distTo(from) );

			x += Math.cos(ang)*step;
			y += Math.sin(ang)*step;
			elapsedDist+=step;
		}


		return null;
	}


	function findClosest(from:MenuGroupElement) : Null<MenuGroupElement> {
		var best = null;
		for(other in elements)
			if( other!=from && ( best==null || from.distTo(other) < from.distTo(best) ) )
				best = other;
		return best;
	}


	public function renderConnectionsDebug(g:h2d.Graphics) {
		g.clear();
		g.removeChildren();
		buildConnections();
		var font = hxd.res.DefaultFont.get();
		for(from in elements) {
			for(dir in [North,East,South,West]) {
				if( !from.hasConnection(dir) )
					continue;

				var next = from.getConnectedElement(dir);
				var ang = from.angTo(next);
				g.lineStyle(2, Yellow);
				g.moveTo(from.centerX, from.centerY);
				g.lineTo(next.centerX, next.centerY);

				// Arrow head
				var arrowDist = 16;
				var arrowAng = M.PI*0.95;
				g.moveTo(next.centerX, next.centerY);
				g.lineTo(next.centerX+Math.cos(ang+arrowAng)*arrowDist, next.centerY+Math.sin(ang+arrowAng)*arrowDist);

				g.moveTo(next.centerX, next.centerY);
				g.lineTo(next.centerX+Math.cos(ang-arrowAng)*arrowDist, next.centerY+Math.sin(ang-arrowAng)*arrowDist);

				var tf = new h2d.Text(font,g);
				tf.text = switch dir {
					case North: 'N';
					case East: 'E';
					case South: 'S';
					case West: 'W';
				}
				tf.x = Std.int( ( from.centerX*0.3 + next.centerX*0.7 ) - tf.textWidth*0.5 );
				tf.y = Std.int( ( from.centerY*0.3 + next.centerY*0.7 ) - tf.textHeight*0.5 );
				tf.filter = new dn.heaps.filter.PixelOutline();
			}
		}
	}


	override function onDispose() {
		super.onDispose();

		ca.dispose();
		ca = null;

		elements = null;
		current = null;
	}

	function focusClosestElementFromGlobal(x:Float, y:Float) {
		var pt = new h2d.col.Point(0,0);
		var best = Lib.findBestInArray(elements, e->{
			pt.set(e.width*0.5, e.height*0.5);
			e.f.localToGlobal(pt);
			return -M.dist(x, y, pt.x, pt.y);
		});
		if( best!=null )
			focusElement(best);
	}

	function focusElement(ge:MenuGroupElement) {
		if( current==ge )
			return;

		if( current!=null )
			current.onBlur();
		current = ge;
		current.onFocus();
	}

	public dynamic function defaultOnFocus(t:MenuGroupElement) {
		t.f.filter = new dn.heaps.filter.PixelOutline(Red);
	}

	public dynamic function defaultOnBlur(t:MenuGroupElement) {
		t.f.filter = null;
	}

	inline function getOppositeDir(dir:MenuDir) {
		return switch dir {
			case North: South;
			case East: West;
			case South: North;
			case West: East;
		}
	}

	inline function dirToAng(dir:MenuDir) : Float {
		return switch dir {
			case North: -M.PIHALF;
			case East: 0;
			case South: M.PIHALF;
			case West: M.PI;
		}
	}

	function angToDir(ang:Float) : MenuDir {
		return  M.radDistance(ang,0)<=M.PIHALF*0.5 ? East
			: M.radDistance(ang,M.PIHALF)<=M.PIHALF*0.5 ? South
			: M.radDistance(ang,M.PI)<=M.PIHALF*0.5 ? West
			: North;
	}


	function gotoNextDir(dir:MenuDir) {
		if( current==null )
			return;

		if( current.hasConnection(dir) )
			focusElement( current.getConnectedElement(dir) );
		else
			gotoConnectedGroup(dir);
	}


	function gotoConnectedGroup(dir:MenuDir) : Bool {
		if( !connectedGroups.exists(dir) )
			return false;

		if( connectedGroups.get(dir).elements.length==0 )
			return false;

		var g = connectedGroups.get(dir);
		var from = current;
		var pt = new h2d.col.Point(from.width*0.5, from.height*0.5);
		from.f.localToGlobal(pt);
		blurGroup();
		g.focusGroup();
		g.focusClosestElementFromGlobal(pt.x, pt.y);
		return true;
	}


	public function connectGroup(dir:MenuDir, targetGroup:MenuGroup, symetric=true) {
		connectedGroups.set(dir,targetGroup);
		if( symetric )
			targetGroup.connectGroup(getOppositeDir(dir), this, false);

		if( focused )
			blurAllConnectedGroups();
	}


	override function preUpdate() {
		super.preUpdate();

		if( !focused )
			return;

		if( connectionsInvalidated ) {
			buildConnections();
			connectionsInvalidated = false;
		}

		if( current==null && elements.length>0 )
			focusElement(elements[0]);

		if( current!=null ) {
			if( ca.isPressed(MenuOk) )
				current.cb();

			if( ca.isPressedAutoFire(MenuLeft) )
				gotoNextDir(West);
			else if( ca.isPressedAutoFire(MenuRight) )
				gotoNextDir(East);

			if( ca.isPressedAutoFire(MenuUp) )
				gotoNextDir(North);
			else if( ca.isPressedAutoFire(MenuDown) )
				gotoNextDir(South);
		}
	}
}



class MenuGroupElement {
	var uid : Int;
	var group : MenuGroup;

	public var f: h2d.Flow;
	public var cb: Void->Void;

	var connections : Map<MenuDir, MenuGroupElement> = new Map();

	public var width(get,never) : Int;
	public var height(get,never) : Int;

	public var left(get,never) : Float;
	public var right(get,never) : Float;
	public var top(get,never) : Float;
	public var bottom(get,never) : Float;

	public var centerX(get,never) : Float;
	public var centerY(get,never) : Float;


	public function new(g,f,cb) {
		uid = MenuGroup.UID++;
		group = g;
		this.f = f;
		this.cb = cb;
		f.onAfterReflow = group.invalidateConnections;
	}

	@:keep public function toString() {
		return 'MenuGroupElement#$uid';
	}

	inline function get_width() return f.outerWidth;
	inline function get_height() return f.outerHeight;

	inline function get_left() return f.x;
	inline function get_right() return left+width;
	inline function get_top() return f.y;
	inline function get_bottom() return top+height;

	inline function get_centerX() return left + width*0.5;
	inline function get_centerY() return top + height*0.5;


	public function connectNext(dir:MenuDir, to:MenuGroupElement, symetric=true) {
		connections.set(dir, to);
		if( symetric )
			to.connections.set(group.getOppositeDir(dir), this);
	}

	public function clearConnections() {
		connections = new Map();
	}

	public function countConnections() {
		var n = 0;
		for(next in connections)
			n++;
		return n;
	}

	public inline function hasConnection(dir:MenuDir) {
		return connections.exists(dir);
	}

	public function isConnectedTo(ge:MenuGroupElement) {
		for(next in connections)
			if( next==ge )
				return true;
		return false;
	}

	public inline function getConnectedElement(dir:MenuDir) {
		return connections.get(dir);
	}

	public inline function angTo(t:MenuGroupElement) {
		return Math.atan2(t.centerY-centerY, t.centerX-centerX);
	}

	public inline function distTo(t:MenuGroupElement) {
		return M.dist(centerX, centerY, t.centerX, t.centerY);
	}

	public dynamic function onFocus() {
		group.defaultOnFocus(this);
	}

	public dynamic function onBlur() {
		group.defaultOnBlur(this);
	}
}
