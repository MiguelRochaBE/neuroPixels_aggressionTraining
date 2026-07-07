import cv2
import numpy as np
from pathlib import Path
import tkinter as tk
from tkinter import filedialog, simpledialog, messagebox
from PIL import Image, ImageTk


class MultiROICropper:
    def __init__(self, root):
        self.root = root
        self.root.title("Multi-ROI Video Cropper")

        self.video_path = None
        self.cap = None
        self.original_first_frame = None
        self.display_frame = None
        self.tk_image = None

        self.rotation_angle = 0

        # ROIs stored in rotated-frame coordinates:
        # [{"name": str, "x": int, "y": int, "w": int, "h": int}]
        self.rois = []

        self.scale = 1.0
        self.canvas_image_offset_x = 0
        self.canvas_image_offset_y = 0

        self.drag_start_x = None
        self.drag_start_y = None
        self.current_rect_id = None

        self.selected_roi_index = None

        self.setup_gui()

    def setup_gui(self):
        main_frame = tk.Frame(self.root)
        main_frame.pack(fill=tk.BOTH, expand=True)

        button_frame = tk.Frame(main_frame)
        button_frame.pack(side=tk.TOP, fill=tk.X, padx=5, pady=5)

        tk.Button(button_frame, text="Open video", command=self.open_video).pack(side=tk.LEFT, padx=3)

        tk.Button(button_frame, text="Rotate -2°", command=lambda: self.rotate_frame(-2)).pack(side=tk.LEFT, padx=3)
        tk.Button(button_frame, text="Rotate +2°", command=lambda: self.rotate_frame(2)).pack(side=tk.LEFT, padx=3)

        tk.Button(button_frame, text="Rotate -90°", command=lambda: self.rotate_frame(-90)).pack(side=tk.LEFT, padx=3)
        tk.Button(button_frame, text="Rotate +90°", command=lambda: self.rotate_frame(90)).pack(side=tk.LEFT, padx=3)

        tk.Button(button_frame, text="Reset rotation", command=self.reset_rotation).pack(side=tk.LEFT, padx=3)

        tk.Button(button_frame, text="Delete selected ROI", command=self.delete_selected_roi).pack(side=tk.LEFT, padx=3)
        tk.Button(button_frame, text="Export ROIs", command=self.export_rois).pack(side=tk.LEFT, padx=3)

        content_frame = tk.Frame(main_frame)
        content_frame.pack(fill=tk.BOTH, expand=True)

        self.canvas = tk.Canvas(content_frame, bg="black", cursor="cross")
        self.canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

        self.roi_listbox = tk.Listbox(content_frame, width=35)
        self.roi_listbox.pack(side=tk.RIGHT, fill=tk.Y, padx=5, pady=5)
        self.roi_listbox.bind("<<ListboxSelect>>", self.on_roi_select)

        self.canvas.bind("<ButtonPress-1>", self.on_mouse_down)
        self.canvas.bind("<B1-Motion>", self.on_mouse_drag)
        self.canvas.bind("<ButtonRelease-1>", self.on_mouse_up)

        self.status_label = tk.Label(main_frame, text="Open a video to begin.", anchor="w")
        self.status_label.pack(side=tk.BOTTOM, fill=tk.X)

    def open_video(self):
        path = filedialog.askopenfilename(
            title="Select video",
            filetypes=[
                ("Video files", "*.mp4 *.avi *.mov *.mkv *.wmv *.mpeg *.mpg"),
                ("All files", "*.*"),
            ],
        )

        if not path:
            return

        self.video_path = Path(path)
        self.cap = cv2.VideoCapture(str(self.video_path))

        if not self.cap.isOpened():
            messagebox.showerror("Error", "Could not open video.")
            return

        ok, frame = self.cap.read()
        if not ok:
            messagebox.showerror("Error", "Could not read first frame.")
            return

        self.original_first_frame = frame
        self.rotation_angle = 0
        self.rois.clear()
        self.selected_roi_index = None
        self.update_roi_listbox()
        self.update_display()

        self.status_label.config(text=f"Loaded: {self.video_path.name}")

    def rotate_frame(self, angle):
        if self.original_first_frame is None:
            return

        self.rotation_angle += angle
        self.rotation_angle = self.rotation_angle % 360

        # Important: changing rotation invalidates old ROI coordinates.
        # This avoids accidental crops from the wrong coordinate system.
        if self.rois:
            answer = messagebox.askyesno(
                "Clear ROIs?",
                "Changing rotation will clear the existing ROIs. Continue?"
            )
            if not answer:
                self.rotation_angle = (self.rotation_angle - angle) % 360
                return

            self.rois.clear()
            self.selected_roi_index = None
            self.update_roi_listbox()

        self.update_display()
        self.status_label.config(text=f"Rotation angle: {self.rotation_angle}°")

    def reset_rotation(self):
        if self.original_first_frame is None:
            return

        if self.rois:
            answer = messagebox.askyesno(
                "Clear ROIs?",
                "Resetting rotation will clear the existing ROIs. Continue?"
            )
            if not answer:
                return

            self.rois.clear()
            self.selected_roi_index = None
            self.update_roi_listbox()

        self.rotation_angle = 0
        self.update_display()
        self.status_label.config(text="Rotation reset to 0°")

    def rotate_bound(self, image, angle):
        """
        Rotate image while keeping the full rotated image visible.
        """
        h, w = image.shape[:2]
        center = (w / 2, h / 2)

        matrix = cv2.getRotationMatrix2D(center, angle, 1.0)

        cos = abs(matrix[0, 0])
        sin = abs(matrix[0, 1])

        new_w = int((h * sin) + (w * cos))
        new_h = int((h * cos) + (w * sin))

        matrix[0, 2] += (new_w / 2) - center[0]
        matrix[1, 2] += (new_h / 2) - center[1]

        rotated = cv2.warpAffine(
            image,
            matrix,
            (new_w, new_h),
            flags=cv2.INTER_LINEAR,
            borderMode=cv2.BORDER_CONSTANT,
            borderValue=(0, 0, 0),
        )

        return rotated

    def get_rotated_first_frame(self):
        return self.rotate_bound(self.original_first_frame, self.rotation_angle)

    def update_display(self):
        if self.original_first_frame is None:
            return

        frame = self.get_rotated_first_frame()
        self.display_frame = frame.copy()

        frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)

        canvas_width = max(self.canvas.winfo_width(), 800)
        canvas_height = max(self.canvas.winfo_height(), 600)

        frame_h, frame_w = frame_rgb.shape[:2]

        self.scale = min(canvas_width / frame_w, canvas_height / frame_h, 1.0)

        resized_w = int(frame_w * self.scale)
        resized_h = int(frame_h * self.scale)

        resized = cv2.resize(frame_rgb, (resized_w, resized_h), interpolation=cv2.INTER_AREA)

        self.canvas.delete("all")

        self.canvas_image_offset_x = (canvas_width - resized_w) // 2
        self.canvas_image_offset_y = (canvas_height - resized_h) // 2

        image = Image.fromarray(resized)
        self.tk_image = ImageTk.PhotoImage(image)

        self.canvas.create_image(
            self.canvas_image_offset_x,
            self.canvas_image_offset_y,
            anchor=tk.NW,
            image=self.tk_image,
        )

        self.draw_rois()

    def draw_rois(self):
        for i, roi in enumerate(self.rois):
            x, y, w, h = roi["x"], roi["y"], roi["w"], roi["h"]

            x1 = self.canvas_image_offset_x + int(x * self.scale)
            y1 = self.canvas_image_offset_y + int(y * self.scale)
            x2 = self.canvas_image_offset_x + int((x + w) * self.scale)
            y2 = self.canvas_image_offset_y + int((y + h) * self.scale)

            color = "yellow" if i == self.selected_roi_index else "red"

            self.canvas.create_rectangle(x1, y1, x2, y2, outline=color, width=2)
            self.canvas.create_text(
                x1 + 5,
                y1 + 10,
                text=roi["name"],
                fill=color,
                anchor=tk.W,
                font=("Arial", 12, "bold"),
            )

    def canvas_to_frame_coords(self, canvas_x, canvas_y):
        frame_x = int((canvas_x - self.canvas_image_offset_x) / self.scale)
        frame_y = int((canvas_y - self.canvas_image_offset_y) / self.scale)
        return frame_x, frame_y

    def on_mouse_down(self, event):
        if self.display_frame is None:
            return

        self.drag_start_x = event.x
        self.drag_start_y = event.y

        self.current_rect_id = self.canvas.create_rectangle(
            event.x,
            event.y,
            event.x,
            event.y,
            outline="cyan",
            width=2,
        )

    def on_mouse_drag(self, event):
        if self.current_rect_id is None:
            return

        self.canvas.coords(
            self.current_rect_id,
            self.drag_start_x,
            self.drag_start_y,
            event.x,
            event.y,
        )

    def on_mouse_up(self, event):
        if self.display_frame is None or self.current_rect_id is None:
            return

        x1_canvas = min(self.drag_start_x, event.x)
        y1_canvas = min(self.drag_start_y, event.y)
        x2_canvas = max(self.drag_start_x, event.x)
        y2_canvas = max(self.drag_start_y, event.y)

        self.canvas.delete(self.current_rect_id)
        self.current_rect_id = None

        x1, y1 = self.canvas_to_frame_coords(x1_canvas, y1_canvas)
        x2, y2 = self.canvas_to_frame_coords(x2_canvas, y2_canvas)

        frame_h, frame_w = self.display_frame.shape[:2]

        x1 = max(0, min(x1, frame_w - 1))
        x2 = max(0, min(x2, frame_w - 1))
        y1 = max(0, min(y1, frame_h - 1))
        y2 = max(0, min(y2, frame_h - 1))

        w = x2 - x1
        h = y2 - y1

        if w < 5 or h < 5:
            self.update_display()
            return

        roi_name = simpledialog.askstring(
            "ROI name",
            "Enter a name for this ROI:",
        )

        if not roi_name:
            roi_name = f"roi_{len(self.rois) + 1}"

        roi_name = self.sanitize_filename(roi_name)

        self.rois.append({
            "name": roi_name,
            "x": x1,
            "y": y1,
            "w": w,
            "h": h,
        })

        self.update_roi_listbox()
        self.update_display()

    def sanitize_filename(self, name):
        bad_chars = '<>:"/\\|?*'
        for ch in bad_chars:
            name = name.replace(ch, "_")
        return name.strip()

    def update_roi_listbox(self):
        self.roi_listbox.delete(0, tk.END)

        for roi in self.rois:
            text = f'{roi["name"]}: x={roi["x"]}, y={roi["y"]}, w={roi["w"]}, h={roi["h"]}'
            self.roi_listbox.insert(tk.END, text)

    def on_roi_select(self, event):
        selection = self.roi_listbox.curselection()

        if not selection:
            self.selected_roi_index = None
        else:
            self.selected_roi_index = selection[0]

        self.update_display()

    def delete_selected_roi(self):
        if self.selected_roi_index is None:
            messagebox.showinfo("No ROI selected", "Select an ROI from the list first.")
            return

        del self.rois[self.selected_roi_index]
        self.selected_roi_index = None
        self.update_roi_listbox()
        self.update_display()

    def export_rois(self):
        if self.video_path is None:
            messagebox.showerror("Error", "No video loaded.")
            return

        if not self.rois:
            messagebox.showerror("Error", "No ROIs selected.")
            return

        output_dir = self.video_path.parent / f"{self.video_path.stem}_cropped_rois"
        output_dir.mkdir(exist_ok=True)

        cap = cv2.VideoCapture(str(self.video_path))

        if not cap.isOpened():
            messagebox.showerror("Error", "Could not reopen video.")
            return

        fps = cap.get(cv2.CAP_PROP_FPS)

        if fps <= 0:
            fps = 30

        writers = []

        try:
            for roi in self.rois:
                output_path = output_dir / f'{roi["name"]}.mp4'

                fourcc = cv2.VideoWriter_fourcc(*"mp4v")

                writer = cv2.VideoWriter(
                    str(output_path),
                    fourcc,
                    fps,
                    (int(roi["w"]), int(roi["h"])),
                )

                if not writer.isOpened():
                    raise RuntimeError(f"Could not create output video: {output_path}")

                writers.append((writer, roi))

            total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
            frame_idx = 0

            self.status_label.config(text="Exporting...")
            self.root.update_idletasks()

            while True:
                ok, frame = cap.read()
                if not ok:
                    break

                rotated = self.rotate_bound(frame, self.rotation_angle)

                for writer, roi in writers:
                    x, y, w, h = roi["x"], roi["y"], roi["w"], roi["h"]
                    crop = rotated[y:y+h, x:x+w]

                    # Safety check in case dimensions are slightly off.
                    if crop.shape[0] != h or crop.shape[1] != w:
                        crop = cv2.resize(crop, (w, h))

                    writer.write(crop)

                frame_idx += 1

                if frame_idx % 50 == 0:
                    self.status_label.config(
                        text=f"Exporting frame {frame_idx}/{total_frames}"
                    )
                    self.root.update_idletasks()

        except Exception as e:
            messagebox.showerror("Export error", str(e))

        finally:
            cap.release()

            for writer, _ in writers:
                writer.release()

        self.status_label.config(text=f"Export complete: {output_dir}")
        messagebox.showinfo(
            "Done",
            f"Saved {len(self.rois)} cropped videos to:\n{output_dir}",
        )


if __name__ == "__main__":
    root = tk.Tk()
    app = MultiROICropper(root)
    root.geometry("1200x800")
    root.mainloop()