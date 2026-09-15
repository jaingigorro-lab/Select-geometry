using System;
using System.Collections.Generic;
using Autodesk.AutoCAD.Geometry;

namespace ConductosPlugin
{
    /// <summary>
    /// Pure math helpers shared by CONDUCTO and CONDUCTORAMAL: no AutoCAD database
    /// access here, just points/angles, so it's easy to reason about (and was checked
    /// by hand against the same formulas already verified in the LISP version).
    /// </summary>
    internal static class GeometryUtil
    {
        public const double AngleWarnTolDeg = 1.0;

        public static double NormPi(double a)
        {
            while (a > Math.PI) a -= 2.0 * Math.PI;
            while (a <= -Math.PI) a += 2.0 * Math.PI;
            return a;
        }

        /// <summary>Deflection angle (0-180 deg) the route turns at vertex v, coming from a and heading to c.</summary>
        public static double DeflectionDeg(Point2d a, Point2d v, Point2d c)
        {
            double hin = AngleTo(a, v);
            double hout = AngleTo(v, c);
            return Math.Abs(NormPi(hout - hin)) * 180.0 / Math.PI;
        }

        public static double AngleTo(Point2d from, Point2d to) => Math.Atan2(to.Y - from.Y, to.X - from.X);

        /// <summary>Z component of the 2D cross product v1 x v2: positive = left turn (CCW), negative = right (CW).</summary>
        public static double Cross2D(Vector2d v1, Vector2d v2) => v1.X * v2.Y - v1.Y * v2.X;

        public static Point2d Polar(Point2d p, double ang, double dist) =>
            new Point2d(p.X + dist * Math.Cos(ang), p.Y + dist * Math.Sin(ang));

        /// <summary>Intersection of the infinite line through p1 (direction dir1) and through p2 (direction dir2). Null if parallel.</summary>
        public static Point2d? LineIntersect(Point2d p1, double dir1, Point2d p2, double dir2)
        {
            double dx1 = Math.Cos(dir1), dy1 = Math.Sin(dir1);
            double dx2 = Math.Cos(dir2), dy2 = Math.Sin(dir2);
            double denom = dx1 * dy2 - dy1 * dx2;
            if (Math.Abs(denom) < 1e-9) return null;
            double t = ((p2.X - p1.X) * dy2 - (p2.Y - p1.Y) * dx2) / denom;
            return new Point2d(p1.X + t * dx1, p1.Y + t * dy1);
        }

        /// <summary>
        /// Drops consecutive duplicate points and interior vertices that are practically
        /// collinear (not a real direction change), so downstream elbow logic never sees
        /// a "straight" vertex.
        /// </summary>
        public static List<Point2d> SimplifyPoints(List<Point2d> pts, double tol)
        {
            var result = new List<Point2d> { pts[0] };
            int n = pts.Count;
            for (int i = 1; i < n - 1; i++)
            {
                Point2d prev = result[result.Count - 1];
                Point2d cur = pts[i];
                Point2d nxt = pts[i + 1];
                if (prev.GetDistanceTo(cur) > tol &&
                    cur.GetDistanceTo(nxt) > tol &&
                    Math.Abs(NormPi(AngleTo(cur, nxt) - AngleTo(prev, cur))) > Math.PI / 360.0)
                {
                    result.Add(cur);
                }
            }
            if (result[result.Count - 1].GetDistanceTo(pts[n - 1]) > tol)
                result.Add(pts[n - 1]);
            return result;
        }
    }
}
