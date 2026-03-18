/* [ Shell ] */
// Enabled
	shellEnabled = true;
// Radius.
	shellRadius = 120;
// Chamber Height.
	shellChamberHeight = 15;
// Top Height
	shellHeightTop = 15;
// Bottom Height
	shellHeightBottom = 8;
// Chambers
	shellChamberChannels = 2;
// Skin Thickness (Suggested: Radius * 0.02)
	shellThickness = 2;

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

/*
	potential features/vairables
		- distinct handle/seam securing bracket piece, using standard notches
		- handle variability or removal
		- top lip inside, outside, disabled
		- more checks to ensure correct placements and that features exist/useful (enough thickness etc)
		- draw mode assembled for preview or printable flat arranged
*/

assert( diskThickness > 0, "Disk should exist." );
$fn = 100;
overlap = 0.001;

module disk(internal = false, offset = 0) {
	diskBite = shellThickness/2; 
    r1 = shellRadius - shellThickness + diskBite + offset; 
    r2 = r1 - diskBite; 
    diskChamferDepth = diskBite;
    diskStraightDepth = diskThickness - diskChamferDepth*2 + ((sqrt(2) - 1) * offset)*2;

	diskCoreThickness = diskThickness * (1 - diskCoreThicknessRatio);
	diskCoreFloor = - diskThickness/2 + diskCoreThickness;
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

	holeWallContact = 0.4; // between chamfer 
	holeWallDesired = 1.2; // between holes
	holeChamfer = (holeWallDesired - holeWallContact)/2;

	// individual grate hole mask/negative
	module holeCutter() {
		h = diskCoreThickness;

		// slice for quasi lofting
		module slice(offset_amount) {
			// to use 3d hulling
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
			union() {
				hull() {
					slice(holeChamfer); 
					translate([0, 0, holeChamfer]) 
					slice(0);
				}

				translate([0, 0, holeChamfer])
					linear_extrude(diskCoreThickness - 2*holeChamfer)
						square([diskHoleSize, diskHoleSizeY], center=true);

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
		dx = (diskHoleType == "rectangle") ? (diskHoleSize + holeWallDesired) : (diskHoleSize + holeWallDesired);
		dy = (diskHoleType == "rectangle") ? (diskHoleSizeY + holeWallDesired) : dx / sin(60);

		// optionally allow overdrawing... kind of looks better to me
		for (x = [-shellRadius: dx : shellRadius]) {
			colIndex = round(x / dx);
			isOdd = (colIndex % 2 != 0);
			yOffset = (diskHoleType != "rectangle" && isOdd) ? dy/2 : 0;

			for (y = [-shellRadius: dy : shellRadius]) {
				// under draw circle check
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
	// Shell
	totalHeight = shellHeightBottom + shellHeightTop + shellChamberHeight * shellChamberChannels;
	// Handle 
	handleSector = 30;
	handleSize = 1;
	handleChord = 2 * shellRadius * sin(handleSector / 2);
	connectorChord = handleChord * 0.8;
	handleFillet = 5;
	connectionDepth = 8 + 2.1*handleFillet * handleSize;     
	handleDepth = 10 * handleSize;   
	handleOuterRadius = shellRadius + connectionDepth + handleDepth ;
	handleInnerRadius = shellRadius + connectionDepth;

	bowOut = shellRadius * (1 - cos(handleSector / 2)); 
	overlap = bowOut + 2; 

	// distributing loop for channels and lips
	module channelDistribute() {
		for(i = [0 : 1 : shellChamberChannels - 1]) {
			translate([0,0,i*shellChamberHeight + shellHeightBottom])
			children();
		}
	}

	// generate internal lips for channels and top
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

	// apply channels loop takes children
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

	// seam
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

	// core shell + bracket extension
	module shellProfile() {
		union() {
			circle(r=shellRadius);
			l = overlap + connectionDepth + 5;
			translate([shellRadius - overlap + l/2, 0])
            square([l, connectorChord], center=true);
		}
	}

	// concentric handle/spring additive
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

	// concentric handle/spring subtractive
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

	// profile assembled
	module profile() {
		module profileFill() {
			difference() {
				union() {
					shellProfile();
					handleAddProfile();
				}
				handleCutProfile();
			}
		}

		union() {
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

	// notch hexagonals
	module notching() {
		notchSize = 2;

		for (z = [0 : totalHeight/3 : totalHeight]) {
			translate([shellRadius + connectionDepth/2 - handleFillet,handleChord/2,z])
			rotate([90,0,0])
			linear_extrude(handleChord)
			circle(notchSize, $fn=6);
		}
	}

	// full assembly: extrude profile, add channels, seam, notches
	module assemble() {
		difference(){ 
			union() {
				channeling()
				linear_extrude(totalHeight)
				profile();
				lip(true);
			}

			linear_extrude(totalHeight*1.5)
			seamCutter();

			notching();
		}
	}

	assemble();
}

render() {
	if (diskEnabled) {
		if (shellEnabled) translate([0,0,shellHeightBottom])
		disk();
	}

	if (shellEnabled) {
		shell();
	}
}
