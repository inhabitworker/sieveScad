/* [ Shell ] */
// Enabled
	shellEnabled = true;
// Radius.
	shellRadius = 120;
// Chamber Height.
	shellChamberHeight = 30;
// Top Height
	shellHeightTop = 5;
// Bottom Height
	shellHeightBottom = 8;
// Chambers
	shellChamberChannels = 1;
// Skin Thickness (Suggested: Radius * 0.02)
	shellThickness = 2;
// Stacking Lip
	shellLipType = "inside"; // [ "inside", "outside", "none" ]
// Handle spring
	handleSector = 30; // [ 15 : 5 : 45 ]
// Handle Spring depth factor
	handleSize = 1; // [ 0.5 : 0.1 : 1.5 ]


/* [ Disk ] */
// Enabled
	diskEnabled = true;
// Disk thickness
	diskThickness = 3;
// Central thickness % (grate, optimise print time)
	diskCoreThicknessRatio = 0.5; // [ 0.1 : 0.1 : 1.0 ]
// Core safety margin, or rim
	diskCoreRadiusRatio = 0.1; // [ 0.01 : 0.01 : 0.99 ]
// Filter hole shape 
	diskHoleType = "hexagon"; // [ "none", "rectangle", "circle", "hexagon" ]
// Filter hole span/diameter (x)
	diskHoleSize = 10;
// Rectangle dimension y
	diskHoleSizeY = 10;

/* [ Other ] */
// Tolerance/Clearance for gaps that will be sealed when assembled.
	tolerance = 0.2;
// Draw 
	drawMode = "assembled"; // [ "assembled", "print" ]

assert( diskThickness > 0, "Disk should probably exist." );
$fn = 100;
overlap = 0.001;

// twist lock clipper
// lip support disk
// revolution lofting for add/remove groove/channel
// mesh reduce depth on disk

// bite question:
// will user get tricky bout this? maybe test thickness/disk depth
// dynamically select max holeChamfer depth (half disk depth) in case


module disk(internal = false, offset = 0) {
	diskBite = shellThickness/2; // locking cut of disk into shell
    r1 = shellRadius - shellThickness + diskBite + offset; // main radius
    r2 = r1 - diskBite; // holeChamfered top/bottom surface radius
    diskChamferDepth = diskBite;
    diskStraightDepth = diskThickness - diskChamferDepth*2 + ((sqrt(2) - 1) * offset)*2;

	diskCoreThickness = diskThickness * (1 - diskCoreThicknessRatio);
	diskCoreFloor = - diskThickness/2 + diskCoreThickness;
	// diskCoreRadius = shellRadius * (1 - diskCoreRadiusRatio);
	diskCoreRadius = shellRadius - shellThickness - shellRadius * diskCoreRadiusRatio;

	// generate half the disk plate
    module diskHalf() {
		union() {
			cylinder(diskStraightDepth/2, r1, r1);
			translate([0,0,diskStraightDepth/2])
			cylinder(diskChamferDepth, r1, r2);
		}
    }
	
	// mirror the same, bore core
    module diskFull() {
		difference() {
			union() {
				diskHalf();
				mirror([0,0,1])
				diskHalf();
			}

			// keep amount from base
			translate([0,0, -diskThickness/2 + diskCoreThickness])
			cylinder(r=diskCoreRadius, h=diskThickness);
		}
	}


	// do some initial pre thinking about chamfers.. 
		// inclusive or exclusive... chamfer really not necessarily crucially important as long as we get some.
		// previously diskCoreThickness/3...
	holeWallContact = 0.4; // between chamfer 
	holeWallDesired = 1.2; // between holes
	holeChamfer = (holeWallDesired - holeWallContact)/2;

	module holeCutter() {
		h = diskCoreThickness;

		// holeChamfer is informed by wall width which gives hard limits

		module slice(offset_amount) {
			// We use offset to expand the rectangle evenly on all sides
			linear_extrude(0.001)
				offset(delta = offset_amount)
					square([diskHoleSize, diskHoleSizeY], center=true);
		}

		translate([0,0,-diskThickness/2])	
		if (diskHoleType == "circle" || diskHoleType == "hexagon") {
			r1 = diskHoleSize/2;
			f = diskHoleType == "hexagon" ? 1/cos(30) : 1;
			fn = diskHoleType == "hexagon" ? 6 : $fn; // gives hexagon

			union() {
				cylinder(h=holeChamfer, r1=(diskHoleSize/2 + holeChamfer)*f, r2=(diskHoleSize/2)*f, $fn=fn);

				translate([0,0,holeChamfer]) 
				cylinder(h=h-2*holeChamfer, r=(diskHoleSize/2)*f, $fn=fn);

				translate([0,0,h-holeChamfer])
				cylinder(h=holeChamfer, r1=(diskHoleSize/2)*f, r2=(diskHoleSize/2 + holeChamfer)*f, $fn=fn);
			}
		} else if (diskHoleType == "rectangle") {
			// introduce rounding by way of offset?
			// cube([diskHoleSize, diskHoleSizeY, h], center=true);

			// w: width, l: length, h: total plate thickness, c: chamfer depth
			union() {
				// 1. Bottom Chamfer (Hull between expanded base and standard size)
				hull() {
					slice(holeChamfer); 
					translate([0, 0, holeChamfer]) 
					slice(0);
				}

				// 2. Middle Straight Section
				translate([0, 0, holeChamfer])
					linear_extrude(diskCoreThickness - 2*holeChamfer)
						square([diskHoleSize, diskHoleSizeY], center=true);

				// 3. Top Chamfer (Hull between standard size and expanded top)
				translate([0, 0, diskCoreThickness - holeChamfer])
				hull() {
					slice(0);
					translate([0, 0, holeChamfer]) 
					slice(holeChamfer);
				}
			}
		}
	}

	// pack hole negatives and intersect the set with internal safety cylinder radius 
	module holeArray() {
		overdraw = true;
		// nesting hex/circular rows with sin(60) 
		dx = (diskHoleType == "rectangle") ? (diskHoleSize + holeWallDesired) : (diskHoleSize + holeWallDesired);
		dy = (diskHoleType == "rectangle") ? (diskHoleSizeY + holeWallDesired) : dx / sin(60);

		// optionally allow overdrawing... kind of looks better to me

		for (x = [-shellRadius: dx : shellRadius]) {
			// Offset every other column for hex packing
			colIndex = round(x / dx);
			isOdd = (colIndex % 2 != 0);
			yOffset = (diskHoleType != "rectangle" && isOdd) ? dy/2 : 0;

			for (y = [-shellRadius: dy : shellRadius]) {
				// Pythagorean check: Is this hole's center inside the core?
				if (!overdraw && sqrt(pow(x, 2) + pow(y + yOffset, 2)) < diskCoreRadius - (diskHoleSize/2)) {
					translate([x, y + yOffset, 0])
					holeCutter();
				} else {
					translate([x, y + yOffset, 0])
					holeCutter();
				}
			}
		}
	}

	if (internal == true) {
		diskFull();
	} else { 
		difference() {
			diskFull();
			if (diskHoleType != "none") {
				intersection() {
					translate([0,0,-diskThickness/2])
					cylinder(r = diskCoreRadius, h=diskThickness*2);
					holeArray();
				}
			}
		}  
	}
}

module shell() {
	totalHeight = shellHeightBottom + shellHeightTop + shellChamberHeight * shellChamberChannels;

	module channelDistribute() {
		for(i = [0 : 1 : shellChamberChannels - 1]) {
			translate([0,0,i*shellChamberHeight + shellHeightBottom])
			children();
		}
	}

	module lip(isTop = false) {
		lipSize = isTop ? shellThickness : diskThickness*1.2;
		lipOffSet = 0.5;
		lipExtension = isTop ? 3 : 0;
		lipTotal = lipSize + lipOffSet;
		stackingTolerance = 0.4;

		height = isTop ? totalHeight - lipTotal - lipExtension/2: - lipTotal - diskThickness/2;

		translate([0,0,height])
		rotate_extrude()
		translate([-(shellRadius-shellThickness),0])
		rotate([1,0])
		difference() {
			translate([-lipOffSet,0])
			offset(lipOffSet)
			difference() {
				translate([-1,0])
				square([lipSize,lipSize + lipExtension]);
				translate([2,0])
				offset(2)
				polygon([[0,0], [5,5], [5,0]]);
			}

			translate([-lipTotal*3,-lipTotal*5])
			square([lipTotal*3,lipTotal*10]);

			if (isTop) {
				translate([0,lipTotal + lipExtension/2])
				square([stackingTolerance,lipExtension]);
			}
			
		}
	}

	module channeling() {
		union() {
			difference() {
				union() {
					children();
					channelDistribute()
					disk(true, shellThickness);
				}
				union() {
					channelDistribute()
					disk(true);
					// clear Core
					translate([0,0,-0.5])
					cylinder(r=(shellRadius-shellThickness), h = totalHeight + 1);
				}
			}
			channelDistribute()
			lip();
		}
	}

	module seamCutter() {
		split = 0.2;
		// add inward protrusion to slice lips 
		// circular half ring of diameter thickness, tangential cut, only thick enough to still print disconnected, 0.2mm~
		translate([shellRadius-shellThickness/2,0])
		union() {
			difference() {
				difference() {
					circle(shellThickness/2 + split);
					circle(shellThickness/2);
				}
				translate([0,-shellThickness,0])
				square([shellThickness*2, shellThickness*2], center=true);
			}

			translate([-shellRadius/2 - shellThickness/2,0])
			square([shellRadius/2,split]);


			translate([shellThickness/2, 0])
			square([shellThickness, split]);
		}
	}

	// Method:
		// create simple 2d shape, naturally inset of the desired result

		// fully integrated handle or bracket prongs with no outer connection?
		// probably easier to design fully integrated

		// main cylinder still distinct part
			// clyinder with channel add channel sub
			// seam cut

		// handle/bracket piece:
			// derive guiding dimension by sector angle
			// straight segment extending out of core shell 
				// enough room for clips/locks/nutsbolts
			// concentric sector area for handle outer.
			// offset offset/bool
			// holes/slots for clip lock nut bolt whatever.
				// as close to skin as possible, without cutting in
				// would need to cut in if skin were really thick, but that is an abuse of use case, so buzz off
			// channelSubs

		// then merge the two.

		// or to get fillets at  the connection point, do much the same but from 2d merge and then need to re-introduce the extension of cylinder in between the handle.

		// fillets did not arise at connection point, rethink:
			// instead of simply providing a rectangle connecting the main circle and the concentric handle, create an additional C ring to offset and subtract, which will confer rounding to connection.
			
	// Handle stuff
	handleChord = 2 * shellRadius * sin(handleSector / 2);
	connectorChord = handleChord * 0.8;
	handleFillet = 5;
	connectionDepth = 10 + 2.1*handleFillet * handleSize;     
	handleDepth = 2*handleFillet * handleSize;   
	handleOuterRadius = shellRadius + connectionDepth + handleDepth ;
	handleInnerRadius = shellRadius + connectionDepth;

	bowOut = shellRadius * (1 - cos(handleSector / 2)); 
	overlap = bowOut + 2; 

	// core shell + bracket extension
	module shellProfile() {
		union() {
			circle(r=shellRadius);
			l = overlap + connectionDepth + 5;
			translate([shellRadius - overlap + l/2, 0])
            square([l, connectorChord], center=true);
		}
	}

	// concentric handle/spring
	module handleAddProfile() {
		offset(handleFillet)
		intersection() {
			translate([handleOuterRadius , 0, 0])
			square([handleOuterRadius ,handleChord], center=true);

			difference() {
				// + some manner of the straight section desired
				circle(handleOuterRadius);
				circle(handleInnerRadius);
			}
		}
	}

	module handleCutProfile() {
		offset(handleFillet)
		difference() {
			difference() {
				// + some manner of the straight section desired
				circle(handleInnerRadius - handleFillet*1.99);
				circle(shellRadius + handleFillet);
			}
			translate([shellRadius, 0, 0])
			square([40,connectorChord], center=true);
		}
	}

	module profileThrown() {
		shellProfile();
		#handleCutProfile();
		handleAddProfile();
	}

	module profile() {
		module profileFill() {
			//offset(shellThickness*1)
			difference() {
				union() {
					shellProfile();
					handleAddProfile();
				}
				handleCutProfile();
			}
		}

		union() {
			// create stroke
			difference() {
				profileFill();
				offset(-shellThickness)
				profileFill();
			}

			difference() {
				circle(r=shellRadius);
				circle(r=shellRadius - shellThickness);
			}
		}
	}

	// profile();

	module assemble() {
		difference(){ 
			union() {
				channeling()
				linear_extrude(totalHeight)
				profile();
				lip(true);
			}

			linear_extrude(totalHeight*1.5)
			#seamCutter();
		}
	}

	assemble();

}

module clippingView() {
	difference() {
		children();
		translate([0,0,-500])
		cube([1000,1000, 1000]);
	}
}

// Draw
render() {
	if (diskEnabled) {
		// if (shellEnabled) translate([0,0,shellHeightBottom])
		// disk();
	}

	if (shellEnabled) {
		shell();
	}
}

/*

	// Shell
		Create total height cylinder at radius
		Add disk channels bulge at chamber interval
		Cut disk channel interior (-thickness)
			disc shapes with 45 deg holeChamfer ending at total radius - thickness
		add handle workpiece, tangential omega type of block in any case
			- bracket has notches and holes for bolts, for locking using additional parts or bands
			- slide lock produces small lips vertically to act as channels for additional slide piece
			- integrated lock produces similar shape to slide lock assembled, but integral and hollow for flexing
		cut through seam.
		slide handle is generated distinctly or boolean split away from workpiece, whichever is simplest 

	// disk
		module can produce a solid, to be used in creation of shell disk channels

		cylinder 45 deg extrude, mirrored
		loop to array holes, by way of arraying a small solid, and then intersecting with a cylinder interior to the broader shell cylinder
		then substract the contained hole part.

	// That's about it. in the broader draw module it can be drawn in assembled positions (disk displaced upwards to (first) channel) 
		// or as printable, disk displaced away by radius of shell, slide lock if existing, oriented 90 deg, for layer lines with a smooth slide normal to shell layer lines
*/