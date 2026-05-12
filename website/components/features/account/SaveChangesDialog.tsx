'use client';

import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';

interface SaveChangesDialogProps {
  open: boolean;
  onYes: () => void;
  onNo: () => void;
}

export function SaveChangesDialog({ open, onYes, onNo }: SaveChangesDialogProps) {
  return (
    <Dialog open={open} onOpenChange={(isOpen) => { if (!isOpen) onNo(); }}>
      <DialogContent className="sm:max-w-sm">
        <DialogHeader>
          <DialogTitle>Save Changes?</DialogTitle>
          <DialogDescription>
            You have unsaved changes on this tab.
          </DialogDescription>
        </DialogHeader>
        <DialogFooter className="gap-2">
          <Button variant="outline" onClick={onNo}>No</Button>
          <Button onClick={onYes}>Yes</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
